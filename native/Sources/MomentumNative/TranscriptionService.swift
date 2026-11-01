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

    /// Tail of the transcription queue. `AsrManager` keeps internal state
    /// across suspension points, and actor reentrancy would otherwise let a
    /// quick transcription interleave with a long note transcription, so
    /// transcriptions run strictly one after another.
    private var queueTail: Task<Void, Never>?

    func transcribe(audioURL: URL, language: TranscriptionLanguage) async throws -> String {
        try await serialized { manager in
            var decoderState = try TdtDecoderState()
            return try await manager.transcribe(
                audioURL,
                decoderState: &decoderState,
                language: language.fluidAudioValue
            ).text
        }
    }

    func transcribe(samples: [Float], language: TranscriptionLanguage) async throws -> String {
        try await serialized { manager in
            var decoderState = try TdtDecoderState()
            return try await manager.transcribe(
                samples,
                decoderState: &decoderState,
                language: language.fluidAudioValue
            ).text
        }
    }

    private func serialized(
        _ work: @escaping @Sendable (AsrManager) async throws -> String
    ) async throws -> String {
        let previous = queueTail
        let task = Task { () async throws -> String in
            await previous?.value
            let manager = try await self.loadManager()
            do {
                return try await work(manager)
            } catch {
                throw TranscriptionError.inferenceFailed(error)
            }
        }
        queueTail = Task { _ = try? await task.value }
        return try await task.value
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
