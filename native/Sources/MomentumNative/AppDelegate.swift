import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let captureCoordinator = CaptureCoordinator()
    private let floatingPillWindowController = FloatingPillWindowController()
    private let hotKeyManager = HotKeyManager()

    private var statusItem: NSStatusItem?
    private var toggleMenuItem: NSMenuItem?
    private var languageMenuItem: NSMenuItem?
    private var apiKeyMenuItem: NSMenuItem?
    private var languageItems: [TranscriptionLanguage: NSMenuItem] = [:]
    private var isRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appIcon = AppAssets.appIcon() {
            NSApplication.shared.applicationIconImage = appIcon
        }

        setupStatusItem()
        setupHotKey()

        Task { @MainActor in
            do {
                try await captureCoordinator.requestMicrophoneAccess()
            } catch {
                NSLog("Microphone access not granted: \(error.localizedDescription)")
                presentErrorAlert(message: error.localizedDescription)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregister()
    }

    @objc
    private func toggleRecording() {
        isRecording.toggle()
        refreshMenuState()

        if isRecording {
            floatingPillWindowController.showRecordingIndicator()

            do {
                try captureCoordinator.startCapture()
            } catch {
                NSLog("Failed to start capture: \(error.localizedDescription)")
                isRecording = false
                refreshMenuState()
                floatingPillWindowController.hideRecordingIndicator()
                presentErrorAlert(message: error.localizedDescription)
            }

            return
        }

        floatingPillWindowController.hideRecordingIndicator()

        Task { @MainActor in
            do {
                let result = try await captureCoordinator.stopCapture()
                NSLog("Capture saved at: \(result.audioURL.path)")
                NSLog("Markdown saved at: \(result.markdownURL.path)")
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
    private func promptForAPIKey() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Set OpenAI API Key"
        alert.informativeText = "Momentum will store the key in ~/Library/Application Support/Momentum/config.json"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let inputField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        inputField.placeholderString = "sk-..."
        inputField.stringValue = AppConfigurationStore.storedAPIKey() ?? ""
        alert.accessoryView = inputField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return
        }

        let apiKey = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            presentErrorAlert(message: "The API key cannot be empty.")
            return
        }

        do {
            try AppConfigurationStore.save(apiKey: apiKey)
            refreshAPIKeyMenuState()
        } catch {
            presentErrorAlert(message: "Failed to save API key: \(error.localizedDescription)")
        }
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

        let apiKeyItem = NSMenuItem(title: "Set OpenAI API Key...", action: #selector(promptForAPIKey), keyEquivalent: "")
        apiKeyItem.target = self
        menu.addItem(apiKeyItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Momentum", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        toggleMenuItem = toggleItem
        languageMenuItem = languageItem
        apiKeyMenuItem = apiKeyItem

        refreshMenuState()
        refreshLanguageMenuState()
        refreshAPIKeyMenuState()
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

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: isRecording ? "stop.circle.fill" : "mic.circle.fill",
                accessibilityDescription: "Momentum"
            )
        }
    }

    private func refreshLanguageMenuState() {
        let selectedLanguage = captureCoordinator.transcriptionLanguage()

        for (language, item) in languageItems {
            item.state = language == selectedLanguage ? .on : .off
        }

        languageMenuItem?.title = "Transcription Language: \(selectedLanguage.menuTitle)"
    }

    private func refreshAPIKeyMenuState() {
        let suffix = AppConfigurationStore.hasStoredAPIKey() ? "Saved" : "Missing"
        apiKeyMenuItem?.title = "Set OpenAI API Key... (\(suffix))"
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
