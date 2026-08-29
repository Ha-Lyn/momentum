@preconcurrency import AVFoundation
import CoreMedia
import CoreGraphics
import Foundation
import os
import ScreenCaptureKit

// Logger with public messages so failures are visible in `log show` /
// Console.app (NSLog interpolations are redacted as <private>).
private let outputAudioLog = Logger(subsystem: "com.momentum.native", category: "output-audio")

enum OutputAudioRecorderError: LocalizedError {
    case permissionDenied
    case contentUnavailable(Error)
    case displayUnavailable
    case alreadyRecording
    case notRecording
    case streamCreationFailed
    case audioFormatUnavailable
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "System audio access was denied. Enable Screen Recording access for Momentum in System Settings > Privacy & Security > Screen Recording, then quit and reopen Momentum (macOS only applies this permission after a relaunch)."
        case .contentUnavailable(let error):
            return "System audio content is unavailable: \(error.localizedDescription)"
        case .displayUnavailable:
            return "No display is available for system audio capture."
        case .alreadyRecording:
            return "System audio recording is already in progress."
        case .notRecording:
            return "No system audio recording is currently in progress."
        case .streamCreationFailed:
            return "Failed to create the system audio capture stream."
        case .audioFormatUnavailable:
            return "The system audio format could not be read."
        case .recordingFailed:
            return "The system audio recording ended without producing a valid file."
        }
    }
}

@MainActor
final class OutputAudioRecorder: NSObject {
    private let fileManager = FileManager.default
    private var stream: SCStream?
    private var writer: OutputAudioWriter?
    // SCStream.addStreamOutput keeps only a weak reference to the output, so
    // the recorder must retain the receiver or every frame is dropped with
    // "streamOutput NOT found".
    private var receiver: OutputAudioStreamReceiver?
    private var currentFileURL: URL?
    private var stopContinuation: CheckedContinuation<URL, Error>?

    func requestAccess() async throws {
        // CGRequestScreenCaptureAccess shows the system prompt at most once. If
        // the user grants access in System Settings, macOS only applies it
        // after the app is relaunched, so a denial here is not permanent state.
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw OutputAudioRecorderError.permissionDenied
        }

        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw OutputAudioRecorderError.contentUnavailable(error)
        }
    }

    func startCapture(timestamp: Date) async throws {
        // Re-check at capture time rather than relying on a launch-time cache,
        // so a permission granted mid-session (followed by relaunch) or revoked
        // mid-session is always reflected.
        guard CGPreflightScreenCaptureAccess() else {
            throw OutputAudioRecorderError.permissionDenied
        }
        guard stream == nil else {
            throw OutputAudioRecorderError.alreadyRecording
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw OutputAudioRecorderError.contentUnavailable(error)
        }

        guard let display = content.displays.first else {
            throw OutputAudioRecorderError.displayUnavailable
        }

        guard let captureDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Momentum Eigenvalues", isDirectory: true) else {
            throw AudioRecorderError.documentsDirectoryUnavailable
        }
        try fileManager.createDirectory(at: captureDirectory, withIntermediateDirectories: true)

        let audioURL = captureDirectory.appendingPathComponent("output-momentum-capture-\(Self.timestampString(timestamp)).wav")
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = false
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let writer = OutputAudioWriter(url: audioURL)
        let receiver = OutputAudioStreamReceiver { [weak writer] sampleBuffer in
            writer?.append(sampleBuffer: sampleBuffer)
        }

        do {
            try stream.addStreamOutput(receiver, type: .audio, sampleHandlerQueue: DispatchQueue(label: "com.momentum.output-audio"))
            try await stream.startCapture()
        } catch {
            try? stream.removeStreamOutput(receiver, type: .audio)
            throw OutputAudioRecorderError.streamCreationFailed
        }

        self.stream = stream
        self.writer = writer
        self.receiver = receiver
        self.currentFileURL = audioURL
    }

    func stopCapture() async throws -> URL {
        guard let stream, let writer, let currentFileURL else {
            throw OutputAudioRecorderError.notRecording
        }

        return try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation
            Task { @MainActor in
                do {
                    try await stream.stopCapture()
                    writer.finish()
                    self.reset()
                    if self.fileManager.fileExists(atPath: currentFileURL.path) {
                        continuation.resume(returning: currentFileURL)
                    } else {
                        continuation.resume(throwing: OutputAudioRecorderError.recordingFailed)
                    }
                } catch {
                    writer.finish()
                    self.reset()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func reset() {
        stream = nil
        writer = nil
        receiver = nil
        currentFileURL = nil
        stopContinuation = nil
    }

    private static func timestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }
}

extension OutputAudioRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("System audio stream stopped: \(error.localizedDescription)")
    }
}

private final class OutputAudioStreamReceiver: NSObject, SCStreamOutput, @unchecked Sendable {
    private let appendHandler: (CMSampleBuffer) -> Void

    init(appendHandler: @escaping (CMSampleBuffer) -> Void) {
        self.appendHandler = appendHandler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        appendHandler(sampleBuffer)
    }
}

private final class OutputAudioWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var targetFormat: AVAudioFormat?

    init(url: URL) {
        self.url = url
    }

    func append(sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            outputAudioLog.error("Sample buffer has no format description; dropping")
            return
        }
        let sourceFormat = AVAudioFormat(cmAudioFormatDescription: description)

        if self.audioFile == nil {
            self.sourceFormat = sourceFormat
            outputAudioLog.info("First system audio buffer: \(sourceFormat, privacy: .public)")

            guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: true) else {
                outputAudioLog.error("Failed to create target audio format")
                return
            }
            self.targetFormat = targetFormat

            guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                outputAudioLog.error("Failed to create audio converter from \(sourceFormat, privacy: .public)")
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
        guard let sourceBuffer = makePCMBuffer(from: sampleBuffer, format: sourceFormat) else {
            outputAudioLog.error("Failed to copy PCM data from sample buffer (format: \(sourceFormat, privacy: .public))")
            return
        }
        guard sourceBuffer.frameLength > 0 else { return }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(sourceBuffer.frameLength) * ratio)) + 16
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        // The input block must hand the buffer over exactly once and then
        // report .noDataNow, otherwise the converter can spin or fail.
        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: targetBuffer, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
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
        audioFile = nil
        converter = nil
        sourceFormat = nil
        targetFormat = nil
        lock.unlock()
    }

    private func makePCMBuffer(from sampleBuffer: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameLength = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return nil }
        pcmBuffer.frameLength = frameLength
        // Pass the buffer's own AudioBufferList pointer. Copying `.pointee`
        // into a local truncates the variable-length struct to a single
        // AudioBuffer, which breaks multi-channel (deinterleaved) formats.
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameLength),
            into: pcmBuffer.mutableAudioBufferList
        )
        return status == noErr ? pcmBuffer : nil
    }
}
