@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import os

// Logger with public messages so failures are visible in `log show` /
// Console.app (NSLog interpolations are redacted as <private>).
private let outputAudioLog = Logger(subsystem: "com.momentum.native", category: "output-audio")

enum OutputAudioRecorderError: LocalizedError {
    case permissionDenied
    case tapCreationFailed(OSStatus)
    case tapFormatUnavailable(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)
    case alreadyRecording
    case notRecording
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "System audio access was denied. Enable Momentum under System Settings > Privacy & Security > Screen & System Audio Recording > System Audio Recording Only."
        case .tapCreationFailed(let status):
            return "Failed to create the system audio tap (error \(status)). Check System Audio Recording access for Momentum in System Settings."
        case .tapFormatUnavailable(let status):
            return "The system audio tap format could not be read (error \(status))."
        case .aggregateDeviceCreationFailed(let status):
            return "Failed to create the system audio capture device (error \(status))."
        case .ioProcCreationFailed(let status):
            return "Failed to attach to the system audio capture device (error \(status))."
        case .deviceStartFailed(let status):
            return "Failed to start system audio capture (error \(status))."
        case .alreadyRecording:
            return "System audio recording is already in progress."
        case .notRecording:
            return "No system audio recording is currently in progress."
        case .recordingFailed:
            return "The system audio recording ended without producing a valid file."
        }
    }
}

/// Captures the computer's output audio using a CoreAudio process tap
/// (macOS 14.4+). Unlike ScreenCaptureKit, this only requires the
/// "System Audio Recording Only" permission instead of full Screen Recording.
@MainActor
final class OutputAudioRecorder {
    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.momentum.output-audio")

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var writer: OutputAudioWriter?
    private var currentFileURL: URL?

    /// Triggers the system-audio-recording permission prompt on first launch
    /// by creating (and immediately destroying) a probe tap.
    func requestAccess() async throws {
        var probeTapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(Self.makeTapDescription(), &probeTapID)
        guard status == noErr, probeTapID != kAudioObjectUnknown else {
            outputAudioLog.error("Probe tap creation failed with status \(status, privacy: .public)")
            throw OutputAudioRecorderError.permissionDenied
        }
        AudioHardwareDestroyProcessTap(probeTapID)
    }

    func startCapture(timestamp: Date) async throws {
        guard tapID == kAudioObjectUnknown else {
            throw OutputAudioRecorderError.alreadyRecording
        }

        guard let captureDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Momentum Eigenvalues", isDirectory: true) else {
            throw AudioRecorderError.documentsDirectoryUnavailable
        }
        try fileManager.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        let audioURL = captureDirectory.appendingPathComponent("output-momentum-capture-\(Self.timestampString(timestamp)).wav")

        let tapDescription = Self.makeTapDescription()
        var tapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard status == noErr, tapID != kAudioObjectUnknown else {
            outputAudioLog.error("Tap creation failed with status \(status, privacy: .public)")
            throw OutputAudioRecorderError.tapCreationFailed(status)
        }

        var cleanupTap = true
        defer {
            if cleanupTap {
                AudioHardwareDestroyProcessTap(tapID)
            }
        }

        let sourceFormat = try Self.readTapFormat(tapID: tapID)
        outputAudioLog.info("System audio tap format: \(sourceFormat, privacy: .public)")

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Momentum Output Capture",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ]
            ],
        ]

        var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID)
        guard status == noErr, aggregateDeviceID != kAudioObjectUnknown else {
            outputAudioLog.error("Aggregate device creation failed with status \(status, privacy: .public)")
            throw OutputAudioRecorderError.aggregateDeviceCreationFailed(status)
        }

        var cleanupAggregate = true
        defer {
            if cleanupAggregate {
                AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            }
        }

        let writer = OutputAudioWriter(url: audioURL, sourceFormat: sourceFormat)

        var ioProcID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDeviceID, ioQueue, Self.makeIOBlock(writer: writer))
        guard status == noErr, let ioProcID else {
            outputAudioLog.error("IO proc creation failed with status \(status, privacy: .public)")
            throw OutputAudioRecorderError.ioProcCreationFailed(status)
        }

        status = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard status == noErr else {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            outputAudioLog.error("Device start failed with status \(status, privacy: .public)")
            throw OutputAudioRecorderError.deviceStartFailed(status)
        }

        cleanupTap = false
        cleanupAggregate = false
        self.tapID = tapID
        self.aggregateDeviceID = aggregateDeviceID
        self.ioProcID = ioProcID
        self.writer = writer
        self.currentFileURL = audioURL
    }

    func stopCapture() async throws -> URL {
        guard tapID != kAudioObjectUnknown, let writer, let currentFileURL else {
            throw OutputAudioRecorderError.notRecording
        }

        if let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        }
        AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        AudioHardwareDestroyProcessTap(tapID)

        // Wait for any in-flight IO callback to drain before finalizing.
        await withCheckedContinuation { continuation in
            ioQueue.async { continuation.resume() }
        }
        writer.finish()
        reset()

        guard fileManager.fileExists(atPath: currentFileURL.path) else {
            throw OutputAudioRecorderError.recordingFailed
        }
        return currentFileURL
    }

    private func reset() {
        tapID = AudioObjectID(kAudioObjectUnknown)
        aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        ioProcID = nil
        writer = nil
        currentFileURL = nil
    }

    /// Builds the CoreAudio IO callback in a nonisolated context. A closure
    /// literal formed inside a @MainActor method inherits main-actor
    /// isolation, and Swift 6 traps (dispatch_assert_queue) when CoreAudio
    /// invokes it on its own IO thread.
    private nonisolated static func makeIOBlock(writer: OutputAudioWriter) -> AudioDeviceIOBlock {
        { _, inputData, _, _, _ in
            writer.append(bufferList: inputData)
        }
    }

    private static func makeTapDescription() -> CATapDescription {
        // Mono mixdown of every process's output audio; we transcribe 16kHz
        // mono, so there is no need to capture stereo.
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "Momentum System Audio Tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        return description
    }

    private static func readTapFormat(tapID: AudioObjectID) throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamDescription = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &streamDescription)
        guard status == noErr, let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw OutputAudioRecorderError.tapFormatUnavailable(status)
        }
        return format
    }

    private static func timestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }
}

private final class OutputAudioWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private let sourceFormat: AVAudioFormat
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var finished = false

    init(url: URL, sourceFormat: AVAudioFormat) {
        self.url = url
        self.sourceFormat = sourceFormat
    }

    func append(bufferList: UnsafePointer<AudioBufferList>) {
        lock.lock()
        defer { lock.unlock() }

        guard !finished else { return }

        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, bufferListNoCopy: bufferList) else {
            outputAudioLog.error("Failed to wrap tap buffer list (format: \(self.sourceFormat, privacy: .public))")
            return
        }
        guard sourceBuffer.frameLength > 0 else { return }

        if audioFile == nil {
            guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: true) else {
                outputAudioLog.error("Failed to create target audio format")
                return
            }
            self.targetFormat = targetFormat

            guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                outputAudioLog.error("Failed to create audio converter from \(self.sourceFormat, privacy: .public)")
                return
            }
            self.converter = converter

            do {
                // Plain WAV (LPCM): no encoder buffering or finalization, so
                // every write lands in the file immediately.
                audioFile = try AVAudioFile(
                    forWriting: url,
                    settings: [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: 16_000,
                        AVNumberOfChannelsKey: 1,
                        AVLinearPCMBitDepthKey: 32,
                        AVLinearPCMIsFloatKey: true,
                        AVLinearPCMIsNonInterleaved: false,
                    ],
                    commonFormat: .pcmFormatFloat32,
                    interleaved: true
                )
            } catch {
                outputAudioLog.error("Failed to create system audio file: \(error.localizedDescription, privacy: .public)")
                return
            }
        }

        guard let converter, let targetFormat, let audioFile else { return }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(sourceBuffer.frameLength) * ratio)) + 16
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        // The input block must hand the buffer over exactly once and then
        // report .noDataNow, otherwise the converter can spin or fail. The
        // block runs synchronously within convert(), so the flag box is safe.
        let consumed = ConsumedFlag()
        var conversionError: NSError?
        let status = converter.convert(to: targetBuffer, error: &conversionError) { _, inputStatus in
            if consumed.value {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed.value = true
            inputStatus.pointee = .haveData
            return sourceBuffer
        }

        if let conversionError {
            outputAudioLog.error("Audio conversion failed: \(conversionError.localizedDescription, privacy: .public)")
            return
        }
        guard status != .error else {
            outputAudioLog.error("Audio conversion returned error status")
            return
        }
        guard targetBuffer.frameLength > 0 else { return }

        do {
            try audioFile.write(from: targetBuffer)
        } catch {
            outputAudioLog.error("Failed to write system audio: \(error.localizedDescription, privacy: .public)")
        }
    }

    func finish() {
        lock.lock()
        finished = true
        audioFile = nil
        converter = nil
        targetFormat = nil
        lock.unlock()
    }
}

private final class ConsumedFlag: @unchecked Sendable {
    var value = false
}
