import AppKit
import os

private let appLog = Logger(subsystem: "com.momentum.native", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    /// Single shared transcription service (one model instance), reused by
    /// note capture and quick transcribe.
    private let transcriptionService: TranscriptionService
    private let captureCoordinator: CaptureCoordinator
    private let floatingPillWindowController = FloatingPillWindowController()
    private let hotKeyManager = HotKeyManager()
    private let accessibilityPermission = AccessibilityPermission()
    private lazy var quickTranscribeCoordinator = QuickTranscribeCoordinator(
        transcriptionService: transcriptionService,
        pill: floatingPillWindowController,
        hotKeyManager: hotKeyManager,
        isNoteRecordingActive: { [weak self] in
            guard let self else { return false }
            return self.isRecording || self.isStartingRecording || self.captureCoordinator.isRecording
        },
        currentLanguage: { [weak self] in
            self?.captureCoordinator.transcriptionLanguage() ?? .automatic
        }
    )

    private var statusItem: NSStatusItem?
    private var toggleMenuItem: NSMenuItem?
    private var languageMenuItem: NSMenuItem?
    private var languageItems: [TranscriptionLanguage: NSMenuItem] = [:]
    private var audioChannelsMenuItem: NSMenuItem?
    private var audioChannelItems: [AudioChannel: NSMenuItem] = [:]
    private var quickTranscribeToggleItem: NSMenuItem?
    private var quickTranscribeShortcutItem: NSMenuItem?
    private var grantAccessibilityItem: NSMenuItem?
    private var shortcutRecorderWindowController: ShortcutRecorderWindowController?
    private var isRecording = false
    private var isStartingRecording = false

    override init() {
        let transcriptionService = TranscriptionService()
        self.transcriptionService = transcriptionService
        captureCoordinator = CaptureCoordinator(transcriptionService: transcriptionService)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appIcon = AppAssets.appIcon() {
            NSApplication.shared.applicationIconImage = appIcon
        }

        setupStatusItem()
        setupHotKey()
        setupQuickTranscribe()

        Task { @MainActor in
            await requestPermissions()
        }

        let transcriptionService = transcriptionService
        Task.detached(priority: .utility) {
            await transcriptionService.prewarm()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregisterAll()
    }

    @objc
    private func toggleRecording() {
        guard !isStartingRecording else { return }

        // Note capture and quick transcribe are mutually exclusive.
        if !isRecording && quickTranscribeCoordinator.isBusy {
            NSSound.beep()
            return
        }

        if !isRecording {
            isStartingRecording = true
        }
        isRecording.toggle()
        refreshMenuState()

        if isRecording {
            floatingPillWindowController.showRecordingIndicator()

            Task { @MainActor in
                do {
                    try await captureCoordinator.startCapture()
                    isStartingRecording = false
                } catch {
                    NSLog("Failed to start capture: \(error.localizedDescription)")
                    isStartingRecording = false
                    isRecording = false
                    refreshMenuState()
                    floatingPillWindowController.hideRecordingIndicator()
                    presentErrorAlert(message: error.localizedDescription)
                }
            }

            return
        }

        floatingPillWindowController.hideRecordingIndicator()

        Task { @MainActor in
            do {
                let results = try await captureCoordinator.stopCapture()
                for result in results {
                    NSLog("\(result.channel.title) capture saved at: \(result.audioURL.path)")
                    NSLog("\(result.channel.title) markdown saved at: \(result.markdownURL.path)")
                }
            } catch {
                NSLog("Failed to stop capture: \(error.localizedDescription)")
                presentErrorAlert(message: error.localizedDescription)
            }
        }
    }

    @objc
    private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    @objc
    private func selectTranscriptionLanguage(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let language = TranscriptionLanguage(rawValue: rawValue)
        else {
            return
        }

        captureCoordinator.setTranscriptionLanguage(language)
        refreshLanguageMenuState()
    }

    @objc
    private func toggleAudioChannel(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let channel = AudioChannel(rawValue: rawValue),
              !isRecording else { return }

        let enabled = !captureCoordinator.selectedAudioChannels().contains(channel)
        if !enabled && captureCoordinator.selectedAudioChannels().count == 1 {
            presentErrorAlert(message: "At least one audio channel must remain selected.")
            return
        }

        captureCoordinator.setAudioChannel(channel, enabled: enabled)
        refreshAudioChannelMenuState()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "Momentum")
            button.imagePosition = .imageOnly
            button.toolTip = "Momentum"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Momentum", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let toggleItem = NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let languageItem = NSMenuItem(title: "Transcription Language", action: nil, keyEquivalent: "")
        let languageSubmenu = NSMenu()

        for language in TranscriptionLanguage.allCases {
            let item = NSMenuItem(
                title: language.menuTitle,
                action: #selector(selectTranscriptionLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language.rawValue
            languageSubmenu.addItem(item)
            languageItems[language] = item
        }

        menu.setSubmenu(languageSubmenu, for: languageItem)
        menu.addItem(languageItem)

        menu.addItem(.separator())

        let quickTranscribeItem = NSMenuItem(
            title: "Quick Transcribe",
            action: #selector(toggleQuickTranscribe),
            keyEquivalent: ""
        )
        quickTranscribeItem.target = self
        menu.addItem(quickTranscribeItem)

        let shortcutItem = NSMenuItem(
            title: "Quick Transcribe Shortcut",
            action: #selector(openShortcutSettings),
            keyEquivalent: ""
        )
        shortcutItem.target = self
        menu.addItem(shortcutItem)

        let accessibilityItem = NSMenuItem(
            title: "Grant Accessibility Access…",
            action: #selector(grantAccessibilityAccess),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(.separator())

        let optionsItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        let optionsSubmenu = NSMenu()
        let channelsItem = NSMenuItem(title: "Audio Channels", action: nil, keyEquivalent: "")
        let channelsSubmenu = NSMenu()

        for channel in AudioChannel.allCases {
            let item = NSMenuItem(title: channel.title, action: #selector(toggleAudioChannel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = channel.rawValue
            channelsSubmenu.addItem(item)
            audioChannelItems[channel] = item
        }

        optionsSubmenu.setSubmenu(channelsSubmenu, for: channelsItem)
        optionsSubmenu.addItem(channelsItem)
        menu.setSubmenu(optionsSubmenu, for: optionsItem)
        menu.addItem(optionsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Momentum", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        item.menu = menu
        statusItem = item
        toggleMenuItem = toggleItem
        languageMenuItem = languageItem
        audioChannelsMenuItem = channelsItem
        quickTranscribeToggleItem = quickTranscribeItem
        quickTranscribeShortcutItem = shortcutItem
        grantAccessibilityItem = accessibilityItem

        refreshMenuState()
        refreshLanguageMenuState()
        refreshAudioChannelMenuState()
        refreshQuickTranscribeMenuState()
    }

    private func setupHotKey() {
        do {
            try registerNoteToggleHotKey()
        } catch {
            NSLog("Failed to register global hotkey: \(error.localizedDescription)")
            presentErrorAlert(message: error.localizedDescription)
        }
    }

    private func registerNoteToggleHotKey() throws {
        let toggle = PushToTalkShortcut.noteToggle
        try hotKeyManager.register(
            id: HotKeyManager.noteToggleID,
            keyCode: toggle.keyCode ?? 0,
            modifiers: toggle.modifiers.carbonFlags,
            onPress: { [weak self] in self?.toggleRecording() }
        )
    }

    // MARK: Quick Transcribe

    private func setupQuickTranscribe() {
        // Never prompt for Accessibility at launch: the menu shows
        // "Grant Accessibility Access…" and the request happens when the
        // user clicks it or turns the feature on.
        quickTranscribeCoordinator.onMonitorError = { [weak self] error in
            guard let self else { return }
            self.refreshQuickTranscribeMenuState()
            let shortcut = self.quickTranscribeCoordinator.shortcut.displayString
            self.presentErrorAlert(
                message: "Quick Transcribe shortcut \(shortcut) could not be registered: \(error.localizedDescription) Choose another one from Quick Transcribe Shortcut…."
            )
        }
        quickTranscribeCoordinator.start()

        accessibilityPermission.startObserving { [weak self] trusted in
            guard let self else { return }
            self.quickTranscribeCoordinator.accessibilityTrustChanged(trusted)
            self.refreshQuickTranscribeMenuState()
        }
    }

    @objc
    private func toggleQuickTranscribe() {
        let enabled = !quickTranscribeCoordinator.isEnabled
        quickTranscribeCoordinator.setEnabled(enabled)

        if enabled && !AccessibilityPermission.isTrusted {
            requestAccessibilityAccess()
        }

        refreshQuickTranscribeMenuState()
    }

    @objc
    private func openShortcutSettings() {
        if shortcutRecorderWindowController == nil {
            let controller = ShortcutRecorderWindowController()
            controller.currentShortcut = { [weak self] in
                self?.quickTranscribeCoordinator.shortcut ?? .default
            }
            controller.applyShortcut = { [weak self] shortcut in
                try self?.quickTranscribeCoordinator.updateShortcut(shortcut)
            }
            controller.onShortcutChanged = { [weak self] in
                self?.refreshQuickTranscribeMenuState()
            }
            controller.onRecordingChanged = { [weak self] recording in
                self?.setGlobalShortcutsSuspended(recording)
            }
            shortcutRecorderWindowController = controller
        }

        shortcutRecorderWindowController?.present()
    }

    /// Pauses the push-to-talk monitor and the ⌘⇧Space note toggle while the
    /// shortcut recorder captures keys: otherwise pressing the current
    /// shortcut there would start a quick transcription or a note recording
    /// (and Carbon hotkeys would swallow the keys before the recorder sees them).
    private func setGlobalShortcutsSuspended(_ suspended: Bool) {
        quickTranscribeCoordinator.setMonitoringSuspended(suspended)

        if suspended {
            hotKeyManager.unregister(id: HotKeyManager.noteToggleID)
        } else {
            do {
                try registerNoteToggleHotKey()
            } catch {
                appLog.error("Failed to re-register the note recording hotkey: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @objc
    private func grantAccessibilityAccess() {
        requestAccessibilityAccess()
    }

    private func requestAccessibilityAccess() {
        if AccessibilityPermission.request() {
            quickTranscribeCoordinator.accessibilityTrustChanged(true)
        } else {
            AccessibilityPermission.openSystemSettings()
        }
        refreshQuickTranscribeMenuState()
    }

    private func refreshQuickTranscribeMenuState() {
        let trusted = AccessibilityPermission.isTrusted
        quickTranscribeToggleItem?.state = quickTranscribeCoordinator.isEnabled ? .on : .off
        let unavailable = quickTranscribeCoordinator.isShortcutUnavailable ? " (unavailable)" : ""
        quickTranscribeShortcutItem?.title = "Quick Transcribe Shortcut: \(quickTranscribeCoordinator.shortcut.displayString)\(unavailable)…"
        grantAccessibilityItem?.isHidden = trusted
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshQuickTranscribeMenuState()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem === toggleMenuItem {
            // Starting a note recording is blocked while a quick
            // transcription is in progress; stopping is always allowed.
            return isRecording || !quickTranscribeCoordinator.isBusy
        }

        return true
    }

    private func refreshMenuState() {
        toggleMenuItem?.title = isRecording ? "Stop Recording" : "Start Recording"
        audioChannelItems.values.forEach { $0.isEnabled = !isRecording }

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: isRecording ? "stop.circle.fill" : "mic.circle.fill",
                accessibilityDescription: "Momentum"
            )
        }
    }

    private func refreshAudioChannelMenuState() {
        let selected = captureCoordinator.selectedAudioChannels()
        for channel in AudioChannel.allCases {
            audioChannelItems[channel]?.state = selected.contains(channel) ? .on : .off
        }
        let titles = AudioChannel.allCases.filter { selected.contains($0) }.map(\.title).joined(separator: ", ")
        audioChannelsMenuItem?.title = "Audio Channels: \(titles)"
    }

    private func requestPermissions() async {
        do {
            try await captureCoordinator.requestMicrophoneAccess()
        } catch {
            NSLog("Microphone access not granted: \(error.localizedDescription)")
            presentErrorAlert(message: error.localizedDescription)
        }

        do {
            try await captureCoordinator.requestOutputAccess()
        } catch {
            NSLog("System audio access not granted: \(error.localizedDescription)")
            presentErrorAlert(message: error.localizedDescription)
        }
    }

    private func refreshLanguageMenuState() {
        let selectedLanguage = captureCoordinator.transcriptionLanguage()

        for (language, item) in languageItems {
            item.state = language == selectedLanguage ? .on : .off
        }

        languageMenuItem?.title = "Transcription Language: \(selectedLanguage.menuTitle)"
    }

    private func presentErrorAlert(message: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Momentum"
        alert.informativeText = message
        alert.runModal()
    }
}
