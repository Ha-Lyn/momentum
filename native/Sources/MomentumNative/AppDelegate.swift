import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let captureCoordinator = CaptureCoordinator()
    private let floatingPillWindowController = FloatingPillWindowController()
    private let hotKeyManager = HotKeyManager()

    private var statusItem: NSStatusItem?
    private var toggleMenuItem: NSMenuItem?
    private var languageMenuItem: NSMenuItem?
    private var languageItems: [TranscriptionLanguage: NSMenuItem] = [:]
    private var audioChannelsMenuItem: NSMenuItem?
    private var audioChannelItems: [AudioChannel: NSMenuItem] = [:]
    private var isRecording = false
    private var isStartingRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appIcon = AppAssets.appIcon() {
            NSApplication.shared.applicationIconImage = appIcon
        }

        setupStatusItem()
        setupHotKey()

        Task { @MainActor in
            await requestPermissions()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregister()
    }

    @objc
    private func toggleRecording() {
        guard !isStartingRecording else { return }

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

        item.menu = menu
        statusItem = item
        toggleMenuItem = toggleItem
        languageMenuItem = languageItem
        audioChannelsMenuItem = channelsItem

        refreshMenuState()
        refreshLanguageMenuState()
        refreshAudioChannelMenuState()
    }

    private func setupHotKey() {
        hotKeyManager.onKeyDown = { [weak self] in
            self?.toggleRecording()
        }

        do {
            try hotKeyManager.register()
        } catch {
            NSLog("Failed to register global hotkey: \(error.localizedDescription)")
            presentErrorAlert(message: error.localizedDescription)
        }
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
