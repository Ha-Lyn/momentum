import FluidAudio
import Foundation
import os

private let transcriptionLog = Logger(subsystem: "com.momentum.native", category: "transcription")

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
    /// In-flight model load. Shared so that concurrent callers (e.g. the
    /// launch prewarm racing a first transcription) await the same load
    /// instead of downloading/loading the model twice across actor
    /// reentrancy points.
    private var loadTask: Task<AsrManager, Error>?

    func prewarm() async throws {
        _ = try await loadManager()
    }

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

    func transcribe(samples: [Float], language: TranscriptionLanguage) async throws -> String {
        let manager = try await loadManager()

        do {
            var decoderState = try TdtDecoderState()
            let result = try await manager.transcribe(
                samples,
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

        let task: Task<AsrManager, Error>
        if let loadTask {
            task = loadTask
        } else {
            task = Task {
                NSLog("Loading local Parakeet TDT v3 transcription model. The first launch may download model files.")
                let models = try await AsrModels.downloadAndLoad(version: .v3)
                let manager = AsrManager(config: .default)
                try await manager.loadModels(models)
                NSLog("Local transcription model loaded.")
                return manager
            }
            loadTask = task
        }

        do {
            let manager = try await task.value
            asrManager = manager
            loadTask = nil
            return manager
        } catch {
            // Allow a later call to retry the load.
            loadTask = nil
            throw TranscriptionError.modelLoadFailed(error)
        }
    }
}

/// Shared local transcription service. Create a single instance and inject it
/// everywhere so the Parakeet model is only loaded once.
struct TranscriptionService: Sendable {
    private let engine: LocalTranscriptionEngine

    init() {
        engine = LocalTranscriptionEngine()
    }

    /// Loads the transcription model ahead of time so the first transcription
    /// is fast. Never throws; failures are logged and the load is retried on
    /// the next transcription.
    func prewarm() async {
        do {
            try await engine.prewarm()
        } catch {
            transcriptionLog.error("Transcription model prewarm failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func transcribe(audioURL: URL, language: TranscriptionLanguage) async throws -> String {
        try await engine.transcribe(audioURL: audioURL, language: language)
    }

    /// Transcribes in-memory 16 kHz mono Float32 samples. FluidAudio rejects
    /// audio shorter than `ASRConstants.minimumAudioDurationSeconds` (0.3 s).
    func transcribe(samples: [Float], language: TranscriptionLanguage) async throws -> String {
        try await engine.transcribe(samples: samples, language: language)
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
