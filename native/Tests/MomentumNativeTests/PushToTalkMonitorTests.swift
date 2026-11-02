import Carbon
import Testing
@testable import MomentumNative

/// Drives the push-to-talk state machine directly (no NSEvent monitors or
/// Carbon hotkeys) with injected modifier/key state.
@MainActor
@Suite("PushToTalkMonitor")
struct PushToTalkMonitorTests {
    private typealias Modifiers = PushToTalkShortcut.ModifierSet

    /// Mutable fake hardware state shared with the monitor's sources.
    private final class FakeKeyboard {
        var modifiers: Modifiers = []
        var keysDown: Set<UInt32> = []
    }

    private final class Recorder {
        var events: [String] = []
    }

    private let keyboard = FakeKeyboard()
    private let recorder = Recorder()
    private let monitor: PushToTalkMonitor

    init() {
        let keyboard = keyboard
        monitor = PushToTalkMonitor(
            hotKeyManager: HotKeyManager(),
            modifierSource: { keyboard.modifiers },
            keyStateSource: { keyboard.keysDown.contains($0) }
        )
        let recorder = recorder
        monitor.onPress = { recorder.events.append("press") }
        monitor.onRelease = { recorder.events.append("release") }
        monitor.onCancel = { recorder.events.append("cancel") }
    }

    // MARK: Modifier-only (⌥⇧)

    private func holdOptionShiftAndArm() {
        monitor.configureForTesting(shortcut: .default)
        keyboard.modifiers = [.option, .shift]
        monitor.handleModifiersChanged([.option], shortcut: .default)
        monitor.handleModifiersChanged([.option, .shift], shortcut: .default)
    }

    @Test func holdingPastArmDelayStartsRecording() {
        holdOptionShiftAndArm()
        #expect(recorder.events.isEmpty)
        monitor.armTimerFired()
        #expect(recorder.events == ["press"])
    }

    @Test func keyDuringArmWindowIsANormalChordAndNeverRecords() {
        // ⌥⇧+→ must keep working: a key inside the arm window disarms.
        holdOptionShiftAndArm()
        monitor.handleInterruption()
        monitor.armTimerFired()
        #expect(recorder.events.isEmpty)
    }

    @Test func extraModifierDuringArmWindowDisarms() {
        holdOptionShiftAndArm()
        keyboard.modifiers = [.option, .shift, .command]
        monitor.handleModifiersChanged([.option, .shift, .command], shortcut: .default)
        monitor.armTimerFired()
        #expect(recorder.events.isEmpty)
    }

    @Test func releasingAModifierWhileRecordingReleases() {
        holdOptionShiftAndArm()
        monitor.armTimerFired()
        keyboard.modifiers = [.option]
        monitor.handleModifiersChanged([.option], shortcut: .default)
        #expect(recorder.events == ["press", "release"])
    }

    @Test func keyWhileRecordingCancelsInsteadOfReleasing() {
        holdOptionShiftAndArm()
        monitor.armTimerFired()
        monitor.handleInterruption()
        keyboard.modifiers = []
        monitor.handleModifiersChanged([], shortcut: .default)
        #expect(recorder.events == ["press", "cancel"])
    }

    @Test func armTimerDoesNotStartWhenHardwareModifiersWereReleased() {
        holdOptionShiftAndArm()
        keyboard.modifiers = [] // release missed by the event stream
        monitor.armTimerFired()
        #expect(recorder.events.isEmpty)
    }

    @Test func watchdogStopsRecordingWhenTheReleaseEventIsMissed() {
        // Secure input: no flagsChanged arrives, but the hardware state shows
        // the modifiers are up, so the watchdog must release.
        holdOptionShiftAndArm()
        monitor.armTimerFired()
        keyboard.modifiers = []
        monitor.checkLiveModifiers()
        #expect(recorder.events == ["press", "release"])
    }

    @Test func watchdogKeepsRecordingWhileModifiersAreHeld() {
        holdOptionShiftAndArm()
        monitor.armTimerFired()
        monitor.checkLiveModifiers()
        #expect(recorder.events == ["press"])
    }

    // MARK: Modifier + key (Carbon)

    private static let controlOptionSpace = PushToTalkShortcut(modifiers: [.control, .option], keyCode: UInt32(kVK_Space))

    @Test func carbonPressAndReleaseRecord() {
        monitor.configureForTesting(shortcut: Self.controlOptionSpace)
        monitor.handleHotKeyPressed()
        monitor.handleHotKeyPressed() // repeat while held is ignored
        monitor.handleHotKeyReleased()
        #expect(recorder.events == ["press", "release"])
    }

    @Test func carbonCancelMakesTheLaterReleaseANoOp() {
        monitor.configureForTesting(shortcut: Self.controlOptionSpace)
        monitor.handleHotKeyPressed()
        monitor.handleInterruption()
        monitor.handleHotKeyReleased()
        #expect(recorder.events == ["press", "cancel"])
    }

    @Test func carbonWatchdogStopsWhenTheKeyIsNoLongerDown() {
        monitor.configureForTesting(shortcut: Self.controlOptionSpace)
        keyboard.keysDown = [UInt32(kVK_Space)]
        monitor.handleHotKeyPressed()
        monitor.checkLiveModifiers()
        #expect(recorder.events == ["press"])
        keyboard.keysDown = []
        monitor.checkLiveModifiers()
        #expect(recorder.events == ["press", "release"])
    }
}
