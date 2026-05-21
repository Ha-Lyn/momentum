import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let captureCoordinator = CaptureCoordinator()
    private let floatingPillWindowController = FloatingPillWindowController()
    private let hotKeyManager = HotKeyManager()

    private var statusItem: NSStatusItem?
    private var toggleMenuItem: NSMenuItem?
    private var isRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupHotKey()

        Task { @MainActor in
            do {
                try await captureCoordinator.requestMicrophoneAccess()
            } catch {
                NSLog("Microphone access not granted: \(error.localizedDescription)")
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
            }
        }
    }

    @objc
    private func quitApplication() {
        NSApplication.shared.terminate(nil)
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
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Momentum", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        toggleMenuItem = toggleItem

        refreshMenuState()
    }

    private func setupHotKey() {
        hotKeyManager.onKeyDown = { [weak self] in
            self?.toggleRecording()
        }

        do {
            try hotKeyManager.register()
        } catch {
            NSLog("Failed to register global hotkey: \(error.localizedDescription)")
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
}
