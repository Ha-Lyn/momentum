import AppKit
import Foundation
import os

// Never log transcript text; lengths and states only.
private let quickTranscribeLog = Logger(subsystem: "com.momentum.native", category: "quick-transcribe")

/// Push-to-talk dictation: hold the shortcut to record the microphone,
/// release to transcribe locally and paste the text into the app that was
/// focused. Nothing is written to disk and no NSAlert is ever shown (it
/// would steal focus from the target app); errors go to the floating pill.
///
/// State machine: idle → recording → transcribing → inserting → idle.
@MainActor
final class QuickTranscribeCoordinator {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case inserting
    }

    /// FluidAudio rejects audio shorter than 0.3 s; shorter presses are
    /// treated as accidental and discarded silently.
    static let minimumDuration: TimeInterval = 0.3
    private static let minimumSampleCount = Int(MicrophoneBufferRecorder.targetSampleRate * minimumDuration)
    private static let errorMessageDuration: TimeInterval = 3.5

    private let recorder = MicrophoneBufferRecorder()
    private let textInserter = TextInserter()
    private let monitor: PushToTalkMonitor
    private let transcriptionService: TranscriptionService
    private let pill: FloatingPillWindowController
    private let isNoteRecordingActive: @MainActor () -> Bool
    private let currentLanguage: @MainActor () -> TranscriptionLanguage

    private(set) var state = State.idle
    private(set) var isEnabled: Bool
    private(set) var shortcut: PushToTalkShortcut
    private var targetApplication: NSRunningApplication?

    /// True while a quick transcription is in progress (not idle). Used to
    /// keep note capture and quick transcribe mutually exclusive.
    var isBusy: Bool {
        state != .idle
    }

    /// Whether the push-to-talk monitor is currently installed.
    var isMonitoring: Bool {
        monitor.isRunning
    }

    init(
        transcriptionService: TranscriptionService,
        pill: FloatingPillWindowController,
        hotKeyManager: HotKeyManager,
        isNoteRecordingActive: @escaping @MainActor () -> Bool,
        currentLanguage: @escaping @MainActor () -> TranscriptionLanguage,
        shortcut: PushToTalkShortcut = .load(),
        isEnabled: Bool = QuickTranscribeSettings.isEnabled
    ) {
        self.transcriptionService = transcriptionService
        self.pill = pill
        self.isNoteRecordingActive = isNoteRecordingActive
        self.currentLanguage = currentLanguage
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        monitor = PushToTalkMonitor(hotKeyManager: hotKeyManager)

        monitor.onPress = { [weak self] in self?.handlePress() }
        monitor.onRelease = { [weak self] in self?.handleRelease() }
        monitor.onCancel = { [weak self] in self?.handleCancel() }
    }

    // MARK: Configuration

    /// Installs the monitor if enabled and Accessibility is trusted.
    /// Call once at launch.
    func start() {
        refreshMonitor()
    }

    /// Enables/disables the feature and persists the setting.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        QuickTranscribeSettings.isEnabled = enabled
        quickTranscribeLog.info("Quick Transcribe enabled=\(enabled, privacy: .public)")
        refreshMonitor()
    }

    /// Validates, applies and persists a new shortcut. If the monitor is
    /// running and the new shortcut cannot be registered (e.g. the hotkey
    /// is taken by another app), the previous shortcut is restored and the
    /// error is rethrown.
    func updateShortcut(_ newShortcut: PushToTalkShortcut) throws {
        if let validationError = newShortcut.validate() {
            throw validationError
        }

        guard newShortcut != shortcut else {
            return
        }

        if monitor.isRunning {
            cancelRecordingIfNeeded()
            do {
                try monitor.update(shortcut: newShortcut)
            } catch {
                quickTranscribeLog.error("Failed to apply shortcut \(newShortcut.displayString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                try? monitor.start(shortcut: shortcut)
                throw error
            }
        }

        shortcut = newShortcut
        newShortcut.persist()
        quickTranscribeLog.info("Quick Transcribe shortcut set to \(newShortcut.displayString, privacy: .public)")
    }

    /// (Re)installs or removes the monitor after the Accessibility trust
    /// state changed. Global event monitors installed while untrusted never
    /// receive events, so they must be recreated once trust is granted.
    func accessibilityTrustChanged(_ trusted: Bool) {
        quickTranscribeLog.info("Accessibility trust changed: trusted=\(trusted, privacy: .public)")
        refreshMonitor(trusted: trusted, forceRestart: trusted)
    }

    private func refreshMonitor(trusted: Bool = AccessibilityPermission.isTrusted, forceRestart: Bool = false) {
        guard isEnabled, trusted else {
            if monitor.isRunning {
                cancelRecordingIfNeeded()
                monitor.stop()
            }
            if isEnabled, !trusted {
                quickTranscribeLog.warning("Quick Transcribe is enabled but Accessibility is not granted; monitor not started")
            }
            return
        }

        guard forceRestart || !monitor.isRunning || monitor.shortcut != shortcut else {
            return
        }

        cancelRecordingIfNeeded()
        do {
            try monitor.start(shortcut: shortcut)
        } catch {
            quickTranscribeLog.error("Failed to start push-to-talk monitor for \(self.shortcut.displayString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Discards an in-progress recording when the monitor goes away (no
    /// release event would ever arrive). Later stages finish on their own.
    private func cancelRecordingIfNeeded() {
        guard state == .recording else {
            return
        }
        quickTranscribeLog.info("Discarding in-progress recording because the monitor is being reconfigured")
        handleCancel()
    }

    // MARK: Push-to-talk events

    private func handlePress() {
        guard state == .idle else {
            quickTranscribeLog.debug("Ignoring push-to-talk press while busy (state=\(String(describing: self.state), privacy: .public))")
            return
        }

        guard !isNoteRecordingActive() else {
            quickTranscribeLog.info("Ignoring push-to-talk press: note recording in progress")
            pill.showMessage("Note recording in progress")
            return
        }

        // The app the user is typing in. If Momentum itself is frontmost,
        // keep it anyway (pasting into Momentum is harmless).
        let target = NSWorkspace.shared.frontmostApplication

        do {
            try recorder.start()
        } catch {
            quickTranscribeLog.error("Failed to start microphone: \(error.localizedDescription, privacy: .public)")
            pill.showMessage(error.localizedDescription, duration: Self.errorMessageDuration)
            return
        }

        targetApplication = target
        state = .recording
        pill.showListening()
        quickTranscribeLog.info("Quick Transcribe recording started (target=\(target?.bundleIdentifier ?? "nil", privacy: .public))")
    }

    private func handleRelease() {
        guard state == .recording else {
            return
        }

        // Leave .recording right away so a new press during the tail or the
        // transcription is ignored.
        state = .transcribing
        Task { @MainActor [weak self] in
            await self?.finishSession()
        }
    }

    private func handleCancel() {
        guard state == .recording else {
            return
        }

        recorder.cancel()
        pill.hide()
        targetApplication = nil
        state = .idle
        quickTranscribeLog.info("Quick Transcribe cancelled")
    }

    // MARK: Session

    private func finishSession() async {
        defer {
            targetApplication = nil
            state = .idle
        }

        let samples = await recorder.stop()
        guard samples.count >= Self.minimumSampleCount else {
            quickTranscribeLog.info("Recording too short (\(samples.count, privacy: .public) samples); discarding")
            pill.hide()
            return
        }

        pill.showTranscribing()

        let transcript: String
        do {
            let language = currentLanguage()
            transcript = try await transcriptionService
                .transcribe(samples: samples, language: language)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            quickTranscribeLog.error("Quick transcription failed: \(error.localizedDescription, privacy: .public)")
            pill.showMessage(error.localizedDescription, duration: Self.errorMessageDuration)
            return
        }

        guard !transcript.isEmpty else {
            quickTranscribeLog.info("Empty transcript; nothing to paste")
            pill.hide()
            return
        }

        state = .inserting
        let result = await textInserter.insert(transcript, into: targetApplication)

        switch result {
        case .confirmed:
            pill.hide()
        case .failed(let reason):
            pill.showMessage(
                "\(reason.userDescription) — transcript copied, press ⌘V",
                duration: Self.errorMessageDuration
            )
        case .unknown:
            pill.showMessage("Transcript copied — press ⌘V if it wasn't pasted", duration: Self.errorMessageDuration)
        }
    }
}
