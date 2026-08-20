import FluidAudio
import Foundation

enum TranscriptionError: LocalizedError {
    case modelLoadFailed(Error)
    case inferenceFailed(Error)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let error):
            return "The local transcription model could not be loaded: \(error.localizedDescription)"
        case .inferenceFailed(let error):
            return "Local transcription failed: \(error.localizedDescription)"
        }
    }
}

private actor LocalTranscriptionEngine {
    private var asrManager: AsrManager?

    func transcribe(audioURL: URL, language: TranscriptionLanguage) async throws -> String {
        let manager = try await loadManager()

        do {
            var decoderState = try TdtDecoderState()
            let result = try await manager.transcribe(
                audioURL,
                decoderState: &decoderState,
                language: language.fluidAudioValue
            )
            return result.text
        } catch {
            throw TranscriptionError.inferenceFailed(error)
        }
    }

    private func loadManager() async throws -> AsrManager {
        if let asrManager {
            return asrManager
        }

        NSLog("Loading local Parakeet TDT v3 transcription model. The first launch may download model files.")

        do {
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            asrManager = manager
            NSLog("Local transcription model loaded.")
            return manager
        } catch {
            throw TranscriptionError.modelLoadFailed(error)
        }
    }
}

struct TranscriptionService: Sendable {
    private let engine: LocalTranscriptionEngine

    init() {
        engine = LocalTranscriptionEngine()
    }

    func transcribe(audioURL: URL, language: TranscriptionLanguage) async throws -> String {
        try await engine.transcribe(audioURL: audioURL, language: language)
    }
}

private extension TranscriptionLanguage {
    var fluidAudioValue: Language? {
        switch self {
        case .automatic:
            return nil
        case .portuguese:
            return .portuguese
        case .english:
            return .english
        }
    }
}
