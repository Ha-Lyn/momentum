import Foundation

struct CaptureResult {
    let audioURL: URL
    let markdownURL: URL
}

@MainActor
final class CaptureCoordinator {
    private let audioRecorder = AudioRecorder()

    func requestMicrophoneAccess() async throws {
        try await audioRecorder.requestMicrophoneAccess()
    }

    func startCapture() throws {
        try audioRecorder.startCapture()
    }

    func stopCapture() async throws -> CaptureResult {
        let audioURL = try await audioRecorder.stopCapture()
        let transcript = try await TranscriptionService().transcribe(audioURL: audioURL)
        let markdownURL = try writeMarkdown(transcript: transcript, nextTo: audioURL)

        return CaptureResult(audioURL: audioURL, markdownURL: markdownURL)
    }

    private func writeMarkdown(transcript: String, nextTo audioURL: URL) throws -> URL {
        let markdownURL = audioURL.deletingPathExtension().appendingPathExtension("md")
        try transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            .write(to: markdownURL, atomically: true, encoding: .utf8)
        return markdownURL
    }
}
