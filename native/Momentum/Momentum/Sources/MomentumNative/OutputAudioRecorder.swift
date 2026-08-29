@preconcurrency import AVFoundation
import CoreMedia
import CoreGraphics
import Foundation
import ScreenCaptureKit

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
            return "System audio access was denied. Enable Screen Recording access for Momentum in System Settings."
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
    private var currentFileURL: URL?
    private var stopContinuation: CheckedContinuation<URL, Error>?
    private(set) var accessAvailable = false

    func requestAccess() async throws {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            accessAvailable = false
            throw OutputAudioRecorderError.permissionDenied
        }

        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            accessAvailable = true
        } catch {
            accessAvailable = false
            throw OutputAudioRecorderError.contentUnavailable(error)
        }
    }

    func startCapture(timestamp: Date) async throws {
        guard accessAvailable else {
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

        let audioURL = captureDirectory.appendingPathComponent("output-momentum-capture-\(Self.timestampString(timestamp)).m4a")
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
                    self.stream = nil
                    self.writer = nil
                    self.currentFileURL = nil
                    self.stopContinuation = nil
                    continuation.resume(returning: currentFileURL)
                } catch {
                    writer.finish()
                    self.stream = nil
                    self.writer = nil
                    self.currentFileURL = nil
                    self.stopContinuation = nil
                    continuation.resume(throwing: error)
                }
            }
        }
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
            return
        }
        let sourceFormat = AVAudioFormat(cmAudioFormatDescription: description)

        if self.audioFile == nil {
            self.sourceFormat = sourceFormat
            let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
            self.targetFormat = targetFormat
            self.converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
            do {
                audioFile = try AVAudioFile(forWriting: url, settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 16_000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ])
            } catch {
                NSLog("Failed to create system audio file: \(error.localizedDescription)")
                return
            }
        }

        guard let sourceBuffer = makePCMBuffer(from: sampleBuffer, format: sourceFormat),
              let converter,
              let targetFormat,
              let audioFile else { return }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(sourceBuffer.frameLength) * ratio)) + 1
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var conversionError: NSError?
        converter.convert(to: targetBuffer, error: &conversionError) { _, status in
            status.pointee = .haveData
            return sourceBuffer
        }
        if conversionError == nil {
            do {
                try audioFile.write(from: targetBuffer)
            } catch {
                NSLog("Failed to write system audio: \(error.localizedDescription)")
            }
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
        var audioBufferList = pcmBuffer.mutableAudioBufferList.pointee
        let status = withUnsafeMutablePointer(to: &audioBufferList) { listPointer in
            CMSampleBufferCopyPCMDataIntoAudioBufferList(
                sampleBuffer,
                at: 0,
                frameCount: Int32(frameLength),
                into: listPointer
            )
        }
        return status == noErr ? pcmBuffer : nil
    }
}
