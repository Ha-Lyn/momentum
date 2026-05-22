import Foundation

struct CaptureResult {
    let audioURL: URL
    let markdownURL: URL
}

enum CaptureCoordinatorError: LocalizedError {
    case transcriptionFailed(audioURL: URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .transcriptionFailed(let audioURL, let underlying):
            return "Transcription failed for \(audioURL.lastPathComponent): \(underlying.localizedDescription)"
        }
    }
}

@MainActor
final class CaptureCoordinator {
    private let audioRecorder = AudioRecorder()
    private var selectedLanguage = TranscriptionLanguage.load()
    private var activeCaptureLanguage: TranscriptionLanguage?

    func requestMicrophoneAccess() async throws {
        try await audioRecorder.requestMicrophoneAccess()
    }

    func transcriptionLanguage() -> TranscriptionLanguage {
        selectedLanguage
    }

    func setTranscriptionLanguage(_ language: TranscriptionLanguage) {
        selectedLanguage = language
        language.persist()
    }

    func startCapture() throws {
        try audioRecorder.startCapture()
        activeCaptureLanguage = selectedLanguage
    }

    func stopCapture() async throws -> CaptureResult {
        let audioURL = try await audioRecorder.stopCapture()
        let language = activeCaptureLanguage ?? selectedLanguage
        activeCaptureLanguage = nil

        let transcript: String

        do {
            transcript = try await TranscriptionService().transcribe(audioURL: audioURL, language: language)
        } catch {
            try? writeTranscriptionError(error, nextTo: audioURL)
            throw CaptureCoordinatorError.transcriptionFailed(audioURL: audioURL, underlying: error)
        }

        let markdownURL = try writeMarkdown(transcript: transcript, nextTo: audioURL)

        return CaptureResult(audioURL: audioURL, markdownURL: markdownURL)
    }

    private func writeMarkdown(transcript: String, nextTo audioURL: URL) throws -> URL {
        let markdownURL = audioURL.deletingPathExtension().appendingPathExtension("md")
        try transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            .write(to: markdownURL, atomically: true, encoding: .utf8)
        return markdownURL
    }

    private func writeTranscriptionError(_ error: Error, nextTo audioURL: URL) throws {
        let errorURL = audioURL
            .deletingPathExtension()
            .appendingPathExtension("transcription-error.txt")

        let message = """
        Transcription failed.
        Audio file: \(audioURL.lastPathComponent)
        Reason: \(error.localizedDescription)
        """

        try message.write(to: errorURL, atomically: true, encoding: .utf8)
    }
}
