import AVFoundation
import Testing
@testable import MomentumNative

/// Exercises the audio route-change path with a real AVAudioEngine by
/// posting `AVAudioEngineConfigurationChange` (no physical device switch
/// needed). Skipped when the test process cannot record from a microphone.
@MainActor
@Suite(
    "MicrophoneBufferRecorder route change",
    .serialized,
    .enabled(if: MicrophoneTestSupport.canRecord, "Requires an authorized microphone")
)
struct MicrophoneBufferRecorderTests {
    @Test func stopAfterConfigurationChangeReturnsCapturedSamples() async throws {
        let recorder = MicrophoneBufferRecorder()
        try recorder.start()
        try await Task.sleep(for: .milliseconds(500))

        try await simulateConfigurationChange(on: recorder)

        // The session stays active until stop(); no removeTap on a dropped engine.
        #expect(recorder.isRecording)
        #expect(recorder.activeEngineForTesting == nil)

        let samples = await recorder.stop()
        #expect(!samples.isEmpty)
        #expect(!recorder.isRecording)
    }

    @Test func cancelAfterConfigurationChangeDoesNotCrash() async throws {
        let recorder = MicrophoneBufferRecorder()
        try recorder.start()
        try await Task.sleep(for: .milliseconds(200))

        try await simulateConfigurationChange(on: recorder)

        recorder.cancel()
        #expect(!recorder.isRecording)
        #expect(await recorder.stop().isEmpty)
    }

    private func simulateConfigurationChange(on recorder: MicrophoneBufferRecorder) async throws {
        let engine = try #require(recorder.activeEngineForTesting)
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
        // The observer is registered on the main queue; let it run.
        for _ in 0..<10 where recorder.activeEngineForTesting != nil {
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

enum MicrophoneTestSupport {
    static var canRecord: Bool {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              AVCaptureDevice.default(for: .audio) != nil
        else {
            return false
        }
        let format = AVAudioEngine().inputNode.outputFormat(forBus: 0)
        return format.sampleRate > 0 && format.channelCount > 0
    }
}
