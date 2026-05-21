import AVFoundation
import Foundation

enum AudioRecorderError: LocalizedError {
    case microphoneAccessDenied
    case alreadyRecording
    case notRecording
    case recorderCreationFailed
    case documentsDirectoryUnavailable
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied:
            return "Microphone access was denied."
        case .alreadyRecording:
            return "A recording is already in progress."
        case .notRecording:
            return "No recording is currently in progress."
        case .recorderCreationFailed:
            return "Failed to create the audio recorder."
        case .documentsDirectoryUnavailable:
            return "The user documents directory is unavailable."
        case .recordingFailed:
            return "The recording ended without producing a valid file."
        }
    }
}

@MainActor
final class AudioRecorder: NSObject {
    private let fileManager = FileManager.default
    private var recorder: AVAudioRecorder?
    private var currentFileURL: URL?
    private var stopContinuation: CheckedContinuation<URL, Error>?

    func requestMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }

            if !granted {
                throw AudioRecorderError.microphoneAccessDenied
            }
        default:
            throw AudioRecorderError.microphoneAccessDenied
        }
    }

    func startCapture() throws {
        if recorder?.isRecording == true {
            throw AudioRecorderError.alreadyRecording
        }

        let captureDirectory = try makeCaptureDirectory()
        let audioURL = captureDirectory.appendingPathComponent("momentum-capture-\(Self.timestampString()).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: audioURL, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = false
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw AudioRecorderError.recorderCreationFailed
        }

        currentFileURL = audioURL
        self.recorder = recorder
    }

    func stopCapture() async throws -> URL {
        guard let recorder, recorder.isRecording else {
            throw AudioRecorderError.notRecording
        }

        return try await withCheckedThrowingContinuation { continuation in
            stopContinuation = continuation
            recorder.stop()
        }
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        defer {
            self.recorder = nil
            currentFileURL = nil
            stopContinuation = nil
        }

        guard flag, let currentFileURL else {
            stopContinuation?.resume(throwing: AudioRecorderError.recordingFailed)
            return
        }

        stopContinuation?.resume(returning: currentFileURL)
    }

    private func makeCaptureDirectory() throws -> URL {
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AudioRecorderError.documentsDirectoryUnavailable
        }

        let captureDirectory = documentsDirectory.appendingPathComponent("Momentum Eigenvalues", isDirectory: true)
        try fileManager.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        return captureDirectory
    }

    private static func timestampString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }
}

extension AudioRecorder: @preconcurrency AVAudioRecorderDelegate {}
