import AppKit
import Foundation
import Testing
@testable import MomentumNative

@MainActor
@Suite("QuickTranscribeCoordinator")
struct QuickTranscribeCoordinatorTests {
    private final class FakeRecorder: QuickTranscribeAudioRecording {
        var startCount = 0
        var stopCount = 0
        var cancelCount = 0
        var samplesToReturn: [Float] = Array(repeating: 0.1, count: 16_000)

        func start() throws {
            startCount += 1
        }

        func stop(tailDuration: TimeInterval) async -> [Float] {
            stopCount += 1
            return samplesToReturn
        }

        func cancel() {
            cancelCount += 1
        }
    }

    private final class FakePill: QuickTranscribePillPresenting {
        var events: [String] = []

        func showListening() {
            events.append("listening")
        }

        func showTranscribing() {
            events.append("transcribing")
        }

        func showMessage(_ text: String, duration: TimeInterval) {
            events.append("message:\(text)")
        }

        func hide() {
            events.append("hide")
        }
    }

    private final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private func makeCoordinator(
        recorder: FakeRecorder,
        pill: FakePill,
        transcript: String = "hello world",
        insertedTexts: Box<[String]> = Box([])
    ) -> QuickTranscribeCoordinator {
        QuickTranscribeCoordinator(
            recorder: recorder,
            pill: pill,
            hotKeyManager: HotKeyManager(),
            transcribeAudio: { _, _ in transcript },
            insertText: { text, _ in
                insertedTexts.value.append(text)
                return .confirmed
            },
            isNoteRecordingActive: { false },
            currentLanguage: { .automatic },
            shortcut: .default,
            isEnabled: false
        )
    }

    private func waitForIdle(_ coordinator: QuickTranscribeCoordinator) async {
        for _ in 0..<50 where coordinator.state != .idle {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func manualRecordingIgnoresPushToTalkReleaseCancelAndMonitorReset() async {
        let recorder = FakeRecorder()
        let pill = FakePill()
        let inserted = Box<[String]>([])
        let coordinator = makeCoordinator(recorder: recorder, pill: pill, insertedTexts: inserted)

        coordinator.toggleManualRecording()
        #expect(coordinator.state == .recording)
        #expect(recorder.startCount == 1)
        #expect(pill.events == ["listening"])

        // Push-to-talk events and monitor reconfiguration must not interrupt a manual take.
        coordinator.handleRelease()
        coordinator.handleCancel()
        coordinator.cancelRecordingIfNeeded()
        #expect(coordinator.state == .recording)
        #expect(recorder.cancelCount == 0)
        #expect(recorder.stopCount == 0)

        // Stopping manually finishes and transcribes the recording.
        coordinator.toggleManualRecording()
        await waitForIdle(coordinator)

        #expect(coordinator.state == .idle)
        #expect(recorder.stopCount == 1)
        #expect(recorder.cancelCount == 0)
        #expect(inserted.value == ["hello world"])
        #expect(pill.events == ["listening", "transcribing", "hide"])
    }

    @Test func pushToTalkPressAndReleaseTranscribesAndInserts() async {
        let recorder = FakeRecorder()
        let pill = FakePill()
        let inserted = Box<[String]>([])
        let coordinator = makeCoordinator(recorder: recorder, pill: pill, insertedTexts: inserted)

        coordinator.handlePress()
        #expect(coordinator.state == .recording)
        #expect(recorder.startCount == 1)

        coordinator.handleRelease()
        await waitForIdle(coordinator)

        #expect(coordinator.state == .idle)
        #expect(recorder.stopCount == 1)
        #expect(recorder.cancelCount == 0)
        #expect(inserted.value == ["hello world"])
        #expect(pill.events == ["listening", "transcribing", "hide"])
    }

    @Test func pushToTalkCancelDiscardsRecording() {
        let recorder = FakeRecorder()
        let pill = FakePill()
        let inserted = Box<[String]>([])
        let coordinator = makeCoordinator(recorder: recorder, pill: pill, insertedTexts: inserted)

        coordinator.handlePress()
        #expect(coordinator.state == .recording)

        coordinator.handleCancel()
        #expect(coordinator.state == .idle)
        #expect(recorder.cancelCount == 1)
        #expect(recorder.stopCount == 0)
        #expect(inserted.value.isEmpty)
        #expect(pill.events == ["listening", "hide"])
    }
}
