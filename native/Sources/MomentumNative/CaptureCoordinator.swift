import Foundation

struct CaptureResult {
    let channel: AudioChannel
    let audioURL: URL
    let markdownURL: URL
}

enum CaptureCoordinatorError: LocalizedError {
    case noChannelsSelected
    case allChannelsFailed
    case transcriptionFailed(audioURL: URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noChannelsSelected:
            return "Select at least one audio channel before starting a recording."
        case .allChannelsFailed:
            return "No selected audio channel produced a recording."
        case .transcriptionFailed(let audioURL, let underlying):
            return "Transcription failed for \(audioURL.lastPathComponent): \(underlying.localizedDescription)"
        }
    }
}

@MainActor
final class CaptureCoordinator {
    private let audioRecorder = AudioRecorder()
    private let outputAudioRecorder = OutputAudioRecorder()
    private let transcriptionService = TranscriptionService()
    private var selectedLanguage = TranscriptionLanguage.load()
    private var activeCaptureLanguage: TranscriptionLanguage?
    private var selectedChannels = AudioChannelSelection.load()
    private var activeChannels: Set<AudioChannel> = []

    func requestMicrophoneAccess() async throws {
        try await audioRecorder.requestMicrophoneAccess()
    }

    func requestOutputAccess() async throws {
        try await outputAudioRecorder.requestAccess()
    }

    func selectedAudioChannels() -> Set<AudioChannel> {
        selectedChannels
    }

    func setAudioChannel(_ channel: AudioChannel, enabled: Bool) {
        if enabled {
            selectedChannels.insert(channel)
        } else {
            selectedChannels.remove(channel)
        }
        AudioChannelSelection.persist(selectedChannels)
    }

    func transcriptionLanguage() -> TranscriptionLanguage {
        selectedLanguage
    }

    func setTranscriptionLanguage(_ language: TranscriptionLanguage) {
        selectedLanguage = language
        language.persist()
    }

    func startCapture() async throws {
        guard !selectedChannels.isEmpty else {
            throw CaptureCoordinatorError.noChannelsSelected
        }

        let timestamp = Date()
        var startedInput = false

        if selectedChannels.contains(.input) {
            try audioRecorder.startCapture(timestamp: timestamp)
            startedInput = true
        }

        do {
            if selectedChannels.contains(.output) {
                try await outputAudioRecorder.startCapture(timestamp: timestamp)
            }
        } catch {
            if startedInput {
                _ = try? await audioRecorder.stopCapture()
            }
            throw error
        }

        activeChannels = selectedChannels
        activeCaptureLanguage = selectedLanguage
    }

    func stopCapture() async throws -> [CaptureResult] {
        let language = activeCaptureLanguage ?? selectedLanguage
        activeCaptureLanguage = nil
        let channels = activeChannels
        activeChannels = []

        var audioURLs: [(AudioChannel, URL)] = []
        var stopErrors: [Error] = []

        if channels.contains(.input) {
            do {
                audioURLs.append((.input, try await audioRecorder.stopCapture()))
            } catch {
                stopErrors.append(error)
            }
        }

        if channels.contains(.output) {
            do {
                audioURLs.append((.output, try await outputAudioRecorder.stopCapture()))
            } catch {
                stopErrors.append(error)
            }
        }

        guard !audioURLs.isEmpty else {
            throw stopErrors.last ?? CaptureCoordinatorError.allChannelsFailed
        }

        var results: [CaptureResult] = []

        for (channel, audioURL) in audioURLs {
            do {
                let transcript = try await transcriptionService.transcribe(audioURL: audioURL, language: language)
                let markdownURL = try writeMarkdown(transcript: transcript, nextTo: audioURL)
                results.append(CaptureResult(channel: channel, audioURL: audioURL, markdownURL: markdownURL))
            } catch {
                try? writeTranscriptionError(error, nextTo: audioURL)
                NSLog("Transcription failed for \(audioURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return results
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
