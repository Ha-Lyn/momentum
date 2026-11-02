import AppKit
import Foundation
import os

private let pushToTalkLog = Logger(subsystem: "com.momentum.native", category: "quick-transcribe")

enum PushToTalkMonitorError: LocalizedError {
    case globalMonitorUnavailable

    var errorDescription: String? {
        switch self {
        case .globalMonitorUnavailable:
            return "The global keyboard monitor could not be installed. Check Accessibility access for Momentum in System Settings."
        }
    }
}

/// Detects press-and-hold of the push-to-talk shortcut and reports
/// `onPress` (start recording), `onRelease` (stop and transcribe) and
/// `onCancel` (discard).
///
/// Two backends:
/// - Modifier-only shortcuts (e.g. ⌥⇧): NSEvent global + local monitors.
///   The exact modifier set must be held for `armDelay` without any other
///   key or click (otherwise it was a normal ⌥⇧+key shortcut and nothing
///   happens). While recording, a key press or click cancels.
///   Global monitors require Accessibility; call `start(shortcut:)` again
///   after trust is granted.
/// - Modifier+key shortcuts (e.g. ⌃⌥Space): Carbon hotkey (id 2) with
///   pressed/released events. The key is swallowed by the system.
@MainActor
final class PushToTalkMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    /// How long the modifiers must be held before recording starts.
    static let armDelay: Duration = .milliseconds(200)
    /// While recording, the live modifier state (modifier-only shortcuts) or
    /// the hotkey's key state (Carbon shortcuts) is re-checked at this
    /// interval as a safety net in case a release event is missed (e.g.
    /// secure input), so recording can never get stuck.
    private static let releaseWatchdogInterval: Duration = .milliseconds(100)

    private enum State {
        case idle
        case armed
        case recording
    }

    private static let monitoredEvents: NSEvent.EventTypeMask = [
        .flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ]

    private let hotKeyManager: HotKeyManager
    /// Live modifier state; hardware state by default, injectable for tests.
    private let modifierSource: @MainActor () -> PushToTalkShortcut.ModifierSet
    /// Whether a key is physically down; hardware state by default.
    private let keyStateSource: @MainActor (UInt32) -> Bool

    private(set) var shortcut: PushToTalkShortcut?
    private var state = State.idle
    private var lastModifiers: PushToTalkShortcut.ModifierSet = []
    private var monitors: [Any] = []
    private var armTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?

    /// True between `start(shortcut:)` and `stop()`.
    var isRunning: Bool {
        shortcut != nil
    }

    init(
        hotKeyManager: HotKeyManager,
        modifierSource: @escaping @MainActor () -> PushToTalkShortcut.ModifierSet = { PushToTalkMonitor.hardwareModifiers() },
        keyStateSource: @escaping @MainActor (UInt32) -> Bool = { PushToTalkMonitor.hardwareKeyIsDown($0) }
    ) {
        self.hotKeyManager = hotKeyManager
        self.modifierSource = modifierSource
        self.keyStateSource = keyStateSource
    }

    /// Test hook: sets the shortcut without installing event monitors or
    /// Carbon hotkeys, so the state machine can be driven directly through
    /// the internal `handle…` entry points.
    func configureForTesting(shortcut: PushToTalkShortcut) {
        stop()
        self.shortcut = shortcut
        lastModifiers = modifierSource()
    }

    /// Starts (or restarts) monitoring `shortcut`. Throws if the Carbon
    /// hotkey for a modifier+key shortcut cannot be registered.
    func start(shortcut: PushToTalkShortcut) throws {
        stop()

        if let keyCode = shortcut.keyCode {
            try hotKeyManager.register(
                id: HotKeyManager.pushToTalkID,
                keyCode: keyCode,
                modifiers: shortcut.modifiers.carbonFlags,
                onPress: { [weak self] in self?.handleHotKeyPressed() },
                onRelease: { [weak self] in self?.handleHotKeyReleased() }
            )
            // The Carbon hotkey only reports press/release; key presses and
            // clicks (e.g. Escape) still need to cancel a recording.
            installInterruptionMonitors()
            pushToTalkLog.info("Push-to-talk hotkey registered: \(shortcut.displayString, privacy: .public)")
        } else {
            try installEventMonitors()
            pushToTalkLog.info("Push-to-talk modifier monitor started: \(shortcut.displayString, privacy: .public)")
        }

        self.shortcut = shortcut
    }

    /// Stops monitoring and resets state silently (no callbacks). Callers
    /// that were recording are responsible for discarding their session.
    func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        hotKeyManager.unregister(id: HotKeyManager.pushToTalkID)
        cancelArmTimer()
        stopReleaseWatchdog()
        state = .idle
        lastModifiers = []

        if shortcut != nil {
            pushToTalkLog.info("Push-to-talk monitor stopped")
        }
        shortcut = nil
    }

    func update(shortcut: PushToTalkShortcut) throws {
        try start(shortcut: shortcut)
    }

    // MARK: Modifier-only backend

    /// Throws if the global monitor cannot be installed: without it the
    /// shortcut never fires in other apps, so the feature must be reported
    /// as unavailable rather than silently inert.
    private func installEventMonitors() throws {
        if !AccessibilityPermission.isTrusted {
            pushToTalkLog.warning("Accessibility is not granted; the global push-to-talk monitor will not receive events from other apps")
        }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: Self.monitoredEvents, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
        } else {
            pushToTalkLog.error("Failed to install the global push-to-talk event monitor")
            throw PushToTalkMonitorError.globalMonitorUnavailable
        }

        // Local monitor: events while Momentum itself is frontmost. The
        // event is always passed through unchanged.
        if let local = NSEvent.addLocalMonitorForEvents(matching: Self.monitoredEvents, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }

        lastModifiers = modifierSource()
    }

    /// Carbon backend: key/click monitors used only to cancel a recording.
    /// Not fatal if unavailable (press/release still work through Carbon).
    private func installInterruptionMonitors() {
        let events: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
        } else {
            pushToTalkLog.warning("Failed to install the push-to-talk interruption monitor; key presses will not cancel recordings")
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handle(_ event: NSEvent) {
        guard let shortcut else {
            return
        }

        if let keyCode = shortcut.keyCode {
            // Carbon backend: any other key press or click while recording
            // cancels (the hotkey's own key is swallowed by Carbon; ignore
            // it defensively). A later release is then a no-op.
            switch event.type {
            case .keyDown where UInt32(event.keyCode) == keyCode:
                break
            case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
                if state == .recording {
                    handleInterruption()
                }
            default:
                break
            }
            return
        }

        switch event.type {
        case .flagsChanged:
            handleModifiersChanged(PushToTalkShortcut.ModifierSet(eventFlags: event.modifierFlags), shortcut: shortcut)
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            handleInterruption()
        default:
            break
        }
    }

    // The `handle…`, `armTimerFired` and `checkLiveModifiers` entry points
    // are internal (not private) so tests can drive the state machine.

    func handleModifiersChanged(_ modifiers: PushToTalkShortcut.ModifierSet, shortcut: PushToTalkShortcut) {
        // Ignore flagsChanged events that do not change the normalized set
        // (e.g. Caps Lock, Fn, or pressing the other side's Shift).
        guard modifiers != lastModifiers else {
            return
        }
        lastModifiers = modifiers

        let matches = modifiers == shortcut.modifiers

        switch state {
        case .idle:
            if matches {
                arm()
            }
        case .armed:
            // The set changed before the arm delay elapsed (an extra modifier
            // was added, or one was released): not a push-to-talk.
            disarm()
        case .recording:
            if !matches {
                finishRecording()
            }
        }
    }

    func handleInterruption() {
        switch state {
        case .idle:
            break
        case .armed:
            // ⌥⇧ was part of a normal shortcut (⌥⇧+key or click).
            disarm()
        case .recording:
            state = .idle
            stopReleaseWatchdog()
            pushToTalkLog.info("Push-to-talk cancelled by key press or click")
            onCancel?()
        }
    }

    private func arm() {
        state = .armed
        cancelArmTimer()
        armTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.armDelay)
            guard !Task.isCancelled else {
                return
            }
            self?.armTimerFired()
        }
    }

    private func disarm() {
        state = .idle
        cancelArmTimer()
    }

    private func cancelArmTimer() {
        armTask?.cancel()
        armTask = nil
    }

    func armTimerFired() {
        armTask = nil
        guard state == .armed, let shortcut else {
            return
        }

        // Re-check the live modifier state in case an event was missed.
        guard modifierSource() == shortcut.modifiers else {
            state = .idle
            return
        }

        state = .recording
        startReleaseWatchdog()
        onPress?()
    }

    private func finishRecording() {
        guard state == .recording else {
            return
        }
        state = .idle
        stopReleaseWatchdog()
        onRelease?()
    }

    private func startReleaseWatchdog() {
        stopReleaseWatchdog()
        watchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.releaseWatchdogInterval)
                guard !Task.isCancelled, let self else {
                    return
                }
                self.checkLiveModifiers()
            }
        }
    }

    private func stopReleaseWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    func checkLiveModifiers() {
        guard state == .recording, let shortcut else {
            return
        }

        if let keyCode = shortcut.keyCode {
            // Carbon backend: if the released event was missed, the key is
            // no longer down; stop so the microphone never stays on.
            if !keyStateSource(keyCode) {
                pushToTalkLog.info("Push-to-talk hotkey release detected by watchdog")
                finishRecording()
            }
            return
        }

        // Read the hardware modifier state, not NSEvent.modifierFlags: the
        // latter reflects the last event this process saw, which goes stale
        // when monitors stop receiving events (e.g. secure input).
        let live = modifierSource()
        if live != shortcut.modifiers {
            pushToTalkLog.info("Push-to-talk release detected by watchdog")
            lastModifiers = live
            finishRecording()
        }
    }

    static func hardwareModifiers() -> PushToTalkShortcut.ModifierSet {
        let flags = CGEventSource.flagsState(.hidSystemState)
        return PushToTalkShortcut.ModifierSet(eventFlags: NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)))
    }

    static func hardwareKeyIsDown(_ keyCode: UInt32) -> Bool {
        CGEventSource.keyState(.hidSystemState, key: CGKeyCode(keyCode))
    }

    // MARK: Carbon backend

    func handleHotKeyPressed() {
        // Carbon can deliver repeated pressed events while the key is held.
        guard state == .idle else {
            return
        }
        state = .recording
        startReleaseWatchdog()
        onPress?()
    }

    func handleHotKeyReleased() {
        finishRecording()
    }
}
