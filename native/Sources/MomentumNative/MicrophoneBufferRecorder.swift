@preconcurrency import AVFoundation
import Foundation
import os

private let quickTranscribeLog = Logger(subsystem: "com.momentum.native", category: "quick-transcribe")

enum MicrophoneBufferRecorderError: LocalizedError {
    case microphoneAccessDenied
    case microphoneAccessPending
    case alreadyRecording
    case noInputDevice
    case converterUnavailable
    case engineStartFailed(Error)

    var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied:
            return "Microphone access was denied. Enable Momentum under System Settings > Privacy & Security > Microphone."
        case .microphoneAccessPending:
            return "Allow microphone access in the system prompt, then try again."
        case .alreadyRecording:
            return "A quick transcription is already recording."
        case .noInputDevice:
            return "No microphone is available."
        case .converterUnavailable:
            return "The microphone audio format is not supported."
        case .engineStartFailed(let error):
            return "The microphone could not be started: \(error.localizedDescription)"
        }
    }
}

/// Records the microphone into memory as 16 kHz mono Float32 samples (the
/// format the transcription model expects). Nothing is written to disk.
///
/// A fresh `AVAudioEngine` is created per session and fully stopped on
/// `stop`/`cancel`, so the microphone indicator is only on while recording.
@MainActor
final class MicrophoneBufferRecorder {
    static let targetSampleRate: Double = 16_000

    private var engine: AVAudioEngine?
    private var accumulator: MicrophoneSampleAccumulator?
    private var configurationObserver: NSObjectProtocol?

    /// True while a session is active: from a successful `start()` until
    /// `stop`/`cancel`. Stays true if the engine was interrupted by an audio
    /// configuration change, so the caller can still `stop()` and get the
    /// samples captured before the interruption.
    var isRecording: Bool {
        accumulator != nil
    }

    #if DEBUG
    /// Test hook: the engine of the active session (nil once a configuration
    /// change has dropped it).
    var activeEngineForTesting: AVAudioEngine? {
        engine
    }
    #endif

    func start() throws {
        guard accumulator == nil else {
            throw MicrophoneBufferRecorderError.alreadyRecording
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            // The prompt has not been answered yet (or never shown): ask now
            // instead of reporting a denial. The user retries once granted.
            Self.requestMicrophoneAccess()
            throw MicrophoneBufferRecorderError.microphoneAccessPending
        default:
            throw MicrophoneBufferRecorderError.microphoneAccessDenied
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            quickTranscribeLog.error("Microphone input format unavailable: \(inputFormat, privacy: .public)")
            throw MicrophoneBufferRecorderError.noInputDevice
        }

        guard let accumulator = MicrophoneSampleAccumulator(inputFormat: inputFormat, targetSampleRate: Self.targetSampleRate) else {
            quickTranscribeLog.error("Failed to create converter from \(inputFormat, privacy: .public)")
            throw MicrophoneBufferRecorderError.converterUnavailable
        }

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: inputFormat,
            block: Self.makeTapBlock(accumulator: accumulator)
        )

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            engine.stop()
            quickTranscribeLog.error("Microphone engine failed to start: \(error.localizedDescription, privacy: .public)")
            throw MicrophoneBufferRecorderError.engineStartFailed(error)
        }

        self.engine = engine
        self.accumulator = accumulator
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleConfigurationChange()
            }
        }

        quickTranscribeLog.info("Microphone recording started (input format: \(inputFormat, privacy: .public))")
    }

    /// Keeps recording for `tailDuration` seconds (so the last syllable
    /// spoken right before the shortcut is released is not cut off), then
    /// stops the engine and returns the captured 16 kHz mono samples.
    /// Returns an empty array if not recording, or if the session was
    /// cancelled during the tail.
    func stop(tailDuration: TimeInterval = 0.15) async -> [Float] {
        guard let sessionAccumulator = accumulator else {
            return []
        }

        if tailDuration > 0, engine?.isRunning == true {
            try? await Task.sleep(for: .seconds(tailDuration))
        }

        // cancel() or another stop() may have ended this session during the tail.
        guard accumulator === sessionAccumulator else {
            return []
        }

        teardown()
        let samples = sessionAccumulator.finish()
        let duration = Double(samples.count) / Self.targetSampleRate
        quickTranscribeLog.info("Microphone recording stopped: \(samples.count, privacy: .public) samples (\(duration, privacy: .public) s)")
        return samples
    }

    /// Stops recording immediately and discards the captured audio.
    func cancel() {
        guard let sessionAccumulator = accumulator else {
            return
        }

        teardown()
        _ = sessionAccumulator.finish()
        quickTranscribeLog.info("Microphone recording cancelled")
    }

    private func handleConfigurationChange() {
        guard let engine, accumulator != nil else {
            return
        }

        // The input device changed (e.g. headset plugged/unplugged) and the
        // engine has already stopped. Do not touch the tap: the node may be
        // detached, and AVAudioNode.removeTap raises an uncatchable
        // Objective-C exception in that state. Just stop and drop the engine
        // (releasing it releases the tap) and keep the samples captured so
        // far for stop(). With `engine == nil`, teardown() skips removeTap.
        quickTranscribeLog.warning("Audio configuration changed while recording; stopping microphone and keeping captured audio")
        removeConfigurationObserver()
        engine.stop()
        self.engine = nil
    }

    private func teardown() {
        removeConfigurationObserver()

        // Only a still-attached session engine has a tap to remove (a
        // configuration change drops the engine without removing it).
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        engine = nil
        accumulator = nil
    }

    private func removeConfigurationObserver() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
    }

    /// Triggers the microphone prompt. Nonisolated so the completion handler
    /// (called on an arbitrary queue) is not main-actor isolated, which
    /// Swift 6 would trap on.
    private nonisolated static func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            quickTranscribeLog.info("Microphone access request finished: granted=\(granted, privacy: .public)")
        }
    }

    /// Builds the tap block in a nonisolated context. A closure literal
    /// formed inside a @MainActor method inherits main-actor isolation, and
    /// Swift 6 traps (dispatch_assert_queue) when AVAudioEngine invokes it on
    /// its realtime audio thread.
    private nonisolated static func makeTapBlock(accumulator: MicrophoneSampleAccumulator) -> AVAudioNodeTapBlock {
        { buffer, _ in
            accumulator.append(buffer)
        }
    }
}

/// Converts tap buffers to 16 kHz mono Float32 and accumulates them.
/// Called from the audio thread; all state is protected by `lock`.
private final class MicrophoneSampleAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let inputFormat: AVAudioFormat
    private let targetFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private var samples: [Float] = []
    private var finished = false

    init?(inputFormat: AVAudioFormat, targetSampleRate: Double) {
        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else {
            return nil
        }

        // Mix all input channels into mono instead of keeping only the first.
        converter.downmix = true

        self.inputFormat = inputFormat
        self.targetFormat = targetFormat
        self.converter = converter
        // Reserve ~30 s up front to avoid reallocations on the audio thread.
        samples.reserveCapacity(Int(targetSampleRate) * 30)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard !finished, buffer.frameLength > 0 else { return }

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 16
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        // Hand the buffer over exactly once, then report .noDataNow so the
        // converter keeps its resampler state for the next tap buffer. The
        // block runs synchronously within convert(), so the flag box is safe.
        let consumed = MicrophoneConsumedFlag()
        var conversionError: NSError?
        let status = converter.convert(to: targetBuffer, error: &conversionError) { _, inputStatus in
            if consumed.value {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed.value = true
            inputStatus.pointee = .haveData
            return buffer
        }

        if let conversionError {
            quickTranscribeLog.error("Microphone audio conversion failed: \(conversionError.localizedDescription, privacy: .public)")
            return
        }
        guard status != .error, targetBuffer.frameLength > 0, let channelData = targetBuffer.floatChannelData else {
            return
        }

        samples.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: Int(targetBuffer.frameLength)))
    }

    /// Stops accepting audio and returns everything captured so far. Any tap
    /// callback still in flight after this point is ignored.
    func finish() -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        finished = true
        let result = samples
        samples = []
        return result
    }
}

private final class MicrophoneConsumedFlag: @unchecked Sendable {
    var value = false
}
