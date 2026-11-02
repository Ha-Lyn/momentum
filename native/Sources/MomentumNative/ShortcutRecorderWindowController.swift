import AppKit
import Carbon
import os

private let shortcutRecorderLog = Logger(subsystem: "com.momentum.native", category: "quick-transcribe")

/// Small settings window for the Quick Transcribe push-to-talk shortcut.
///
/// Shows the current shortcut and lets the user record a new one:
/// - modifiers + key (e.g. ⌃⌥Space): captured on keyDown;
/// - modifier-only (e.g. ⌥⇧): the largest set of modifiers held, captured
///   when all of them are released without any key pressed in between.
///
/// The candidate is applied through `applyShortcut`, which validates,
/// persists and registers it (throwing on failure). While recording,
/// `onRecordingChanged(true)` is called so the owner can pause the global
/// shortcuts that would otherwise fire (or swallow the keys).
@MainActor
final class ShortcutRecorderWindowController: NSWindowController, NSWindowDelegate {
    /// Returns the shortcut currently in use.
    var currentShortcut: () -> PushToTalkShortcut = { .default }
    /// Validates, persists and registers a new shortcut; throws on failure.
    var applyShortcut: (PushToTalkShortcut) throws -> Void = { _ in }
    /// Called after a shortcut was applied successfully.
    var onShortcutChanged: (() -> Void)?
    /// Called when recording mode starts (`true`) or ends (`false`).
    var onRecordingChanged: ((Bool) -> Void)?

    private static let idleHint = "Hold the shortcut to dictate, release to paste."
    private static let recordingHint = "Press the new shortcut… (Esc to cancel)"
    private static let missingModifierHint = "Include at least one modifier (⌃ ⌥ ⇧ ⌘)"

    private let shortcutLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private lazy var recordButton = NSButton(title: "Record New Shortcut", target: self, action: #selector(toggleRecording))
    private lazy var restoreButton = NSButton(title: "Restore Default", target: self, action: #selector(restoreDefault))
    private lazy var doneButton = NSButton(title: "Done", target: self, action: #selector(done))

    private var eventMonitor: Any?
    /// Largest modifier set held during the current flagsChanged sequence.
    private var heldModifiers: PushToTalkShortcut.ModifierSet = []
    /// A key was pressed during the current modifier sequence, so releasing
    /// the modifiers must not produce a modifier-only candidate.
    private var keyPressedDuringSequence = false

    private var isRecording: Bool {
        eventMonitor != nil
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Quick Transcribe Shortcut"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the window (reusing it if already open) and activates the app.
    func present() {
        guard let window else {
            return
        }

        if !window.isVisible {
            stopRecording()
            showIdleStatus()
            window.center()
        }
        refreshShortcutLabel()

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Layout

    private func buildContent(in window: NSWindow) {
        let titleLabel = NSTextField(labelWithString: "Current shortcut:")
        titleLabel.textColor = .secondaryLabelColor

        shortcutLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        shortcutLabel.alignment = .center
        shortcutLabel.lineBreakMode = .byTruncatingTail

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        statusLabel.preferredMaxLayoutWidth = 320

        doneButton.keyEquivalent = "\r"
        [recordButton, restoreButton, doneButton].forEach { $0.bezelStyle = .push }

        let buttons = NSStackView(views: [recordButton, restoreButton, doneButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [titleLabel, shortcutLabel, statusLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            contentView.widthAnchor.constraint(equalToConstant: 360),
        ])
        window.contentView = contentView
    }

    private func refreshShortcutLabel() {
        shortcutLabel.stringValue = currentShortcut().displayString
    }

    private func showIdleStatus() {
        showStatus(Self.idleHint)
    }

    private func showStatus(_ text: String, isError: Bool = false) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    // MARK: Actions

    @objc
    private func toggleRecording() {
        if isRecording {
            cancelRecording()
        } else {
            startRecording()
        }
    }

    @objc
    private func restoreDefault() {
        apply(.default)
    }

    @objc
    private func done() {
        window?.close()
    }

    // MARK: Recording

    private func startRecording() {
        guard !isRecording else {
            return
        }

        heldModifiers = []
        keyPressedDuringSequence = false
        onRecordingChanged?(true)

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            // Main thread; a nil result consumes the event.
            guard let self else {
                return event
            }
            return self.handleRecordingEvent(event)
        }

        recordButton.title = "Cancel"
        shortcutLabel.stringValue = "…"
        showStatus(Self.recordingHint)
        shortcutRecorderLog.info("Shortcut recording started")
    }

    private func cancelRecording() {
        guard isRecording else {
            return
        }
        stopRecording()
        refreshShortcutLabel()
        showIdleStatus()
        shortcutRecorderLog.info("Shortcut recording cancelled")
    }

    /// Leaves recording mode (no UI text changes besides the button).
    private func stopRecording() {
        guard let eventMonitor else {
            return
        }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
        heldModifiers = []
        keyPressedDuringSequence = false
        recordButton.title = "Record New Shortcut"
        onRecordingChanged?(false)
    }

    private func handleRecordingEvent(_ event: NSEvent) -> NSEvent? {
        guard window?.isKeyWindow == true else {
            return event
        }

        switch event.type {
        case .flagsChanged:
            handleFlagsChanged(event)
            return event
        case .keyDown:
            handleKeyDown(event)
            // Consume every key while recording (no beeps, no key equivalents).
            return nil
        default:
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let modifiers = PushToTalkShortcut.ModifierSet(eventFlags: event.modifierFlags)

        if !modifiers.isEmpty {
            heldModifiers.formUnion(modifiers)
            shortcutLabel.stringValue = heldModifiers.displayString
            return
        }

        // All modifiers released.
        let candidate = heldModifiers
        let keyPressed = keyPressedDuringSequence
        heldModifiers = []
        keyPressedDuringSequence = false

        guard !candidate.isEmpty, !keyPressed else {
            return
        }
        apply(PushToTalkShortcut(modifiers: candidate, keyCode: nil))
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard !event.isARepeat else {
            return
        }

        let modifiers = PushToTalkShortcut.ModifierSet(eventFlags: event.modifierFlags)
        let keyCode = UInt32(event.keyCode)

        // Esc always cancels, even with modifiers still held (users often
        // press it mid-chord); it must never become a global hotkey.
        if keyCode == UInt32(kVK_Escape) {
            cancelRecording()
            return
        }

        guard !modifiers.isEmpty else {
            shortcutLabel.stringValue = "…"
            showStatus(Self.missingModifierHint, isError: true)
            return
        }

        keyPressedDuringSequence = true
        apply(PushToTalkShortcut(modifiers: modifiers, keyCode: keyCode))
    }

    /// Applies `shortcut`. On success leaves recording mode; on failure
    /// shows the error and keeps recording (if it was) so the user can try
    /// another combination right away.
    private func apply(_ shortcut: PushToTalkShortcut) {
        do {
            try applyShortcut(shortcut)
        } catch {
            shortcutRecorderLog.info("Shortcut \(shortcut.displayString, privacy: .public) rejected: \(error.localizedDescription, privacy: .public)")
            if isRecording {
                shortcutLabel.stringValue = shortcut.displayString
            }
            showStatus(error.localizedDescription, isError: true)
            return
        }

        stopRecording()
        refreshShortcutLabel()
        showStatus("Shortcut set to \(shortcut.displayString).")
        onShortcutChanged?()
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        stopRecording()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Local monitors only see Momentum's events; do not leave the global
        // shortcuts paused while the user is in another app.
        cancelRecording()
    }
}
