import AppKit
import ApplicationServices
import Foundation
import os

private let accessibilityLog = Logger(subsystem: "com.momentum.native", category: "accessibility")

/// Accessibility (AX) trust helpers plus a lightweight observer that polls
/// `AXIsProcessTrusted()` so the app can react when the user grants (or
/// revokes) access in System Settings. macOS posts no notification for this,
/// so polling is the only reliable option.
@MainActor
final class AccessibilityPermission {
    /// Polling interval for the observer.
    static let pollInterval: TimeInterval = 2.0

    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    private var timer: Timer?
    private var lastKnownState: Bool?
    private var onChange: (@MainActor (Bool) -> Void)?

    /// Whether this process is currently trusted for Accessibility.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system Accessibility prompt (if not trusted yet) and asks
    /// for permission to post synthesized events. Safe to call repeatedly;
    /// macOS only prompts when access has not been granted.
    @discardableResult
    static func request() -> Bool {
        // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt;
        // the literal avoids touching the imported global under Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        let canPostEvents = CGRequestPostEventAccess()
        accessibilityLog.info(
            "Accessibility requested: trusted=\(trusted, privacy: .public) postEventAccess=\(canPostEvents, privacy: .public)"
        )
        return trusted
    }

    /// Opens System Settings > Privacy & Security > Accessibility.
    static func openSystemSettings() {
        guard let url = settingsURL else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Starts polling the trust state every `pollInterval` seconds and calls
    /// `onChange` whenever it flips (not for the initial state). Polling keeps
    /// running while trusted too, so revocation is also reported; the check
    /// is a cheap in-process call.
    func startObserving(onChange: @escaping @MainActor (Bool) -> Void) {
        stopObserving()

        self.onChange = onChange
        lastKnownState = Self.isTrusted

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            // Scheduled on the main run loop, so this always runs on the main thread.
            MainActor.assumeIsolated {
                self.poll()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopObserving() {
        timer?.invalidate()
        timer = nil
        onChange = nil
        lastKnownState = nil
    }

    private func poll() {
        let trusted = Self.isTrusted
        guard trusted != lastKnownState else {
            return
        }

        lastKnownState = trusted
        accessibilityLog.info("Accessibility trust changed: trusted=\(trusted, privacy: .public)")
        onChange?(trusted)
    }
}
