import AppKit
import ApplicationServices
import Carbon
import Foundation
import os

// Results are logged with public privacy; the transcript itself is never logged.
private let textInserterLog = Logger(subsystem: "com.momentum.native", category: "text-inserter")

// MARK: - Result types

enum InsertFailureReason: Equatable, Sendable {
    case noAccessibilityPermission
    case eventPostFailed
    case secureInputActive
    case targetAppTerminated
    case targetActivationFailed
    case pasteNotDetected

    /// Short user-facing description, suitable for the floating pill.
    var userDescription: String {
        switch self {
        case .noAccessibilityPermission:
            return "Accessibility access is required to paste"
        case .eventPostFailed:
            return "Could not send the paste shortcut"
        case .secureInputActive:
            return "Secure input is active"
        case .targetAppTerminated:
            return "The target app was closed"
        case .targetActivationFailed:
            return "Could not switch back to the target app"
        case .pasteNotDetected:
            return "The paste was not detected"
        }
    }

    /// Stable identifier for logs.
    var logName: String {
        switch self {
        case .noAccessibilityPermission: return "noAccessibilityPermission"
        case .eventPostFailed: return "eventPostFailed"
        case .secureInputActive: return "secureInputActive"
        case .targetAppTerminated: return "targetAppTerminated"
        case .targetActivationFailed: return "targetActivationFailed"
        case .pasteNotDetected: return "pasteNotDetected"
        }
    }
}

enum InsertResult: Equatable, Sendable {
    /// The focused text element changed after ⌘V; the previous clipboard was restored.
    case confirmed
    /// The paste failed or was not detected; the transcript is left on the clipboard.
    case failed(InsertFailureReason)
    /// ⌘V was sent but the target app does not expose enough AX data to verify it;
    /// the transcript is left on the clipboard.
    case unknown

    var logName: String {
        switch self {
        case .confirmed: return "confirmed"
        case .failed(let reason): return "failed(\(reason.logName))"
        case .unknown: return "unknown"
        }
    }
}

// MARK: - Pasteboard snapshot

/// A full copy of the general pasteboard: every item with every type's data.
struct PasteboardSnapshot: Sendable {
    struct Item: Sendable {
        var representations: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    let items: [Item]

    init(items: [Item]) {
        self.items = items
    }

    /// Captures all items and all of their types from `pasteboard`.
    @MainActor
    init(capturing pasteboard: NSPasteboard) {
        let pasteboardItems = pasteboard.pasteboardItems ?? []
        items = pasteboardItems.map { item in
            let representations = item.types.compactMap { type -> (type: NSPasteboard.PasteboardType, data: Data)? in
                guard let data = item.data(forType: type) else {
                    return nil
                }
                return (type: type, data: data)
            }
            return Item(representations: representations)
        }
    }

    var isEmpty: Bool {
        items.allSatisfy { $0.representations.isEmpty }
    }

    /// Replaces the contents of `pasteboard` with this snapshot.
    @MainActor
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let pasteboardItems: [NSPasteboardItem] = items.compactMap { item in
            guard !item.representations.isEmpty else {
                return nil
            }
            let pasteboardItem = NSPasteboardItem()
            for representation in item.representations {
                pasteboardItem.setData(representation.data, forType: representation.type)
            }
            return pasteboardItem
        }

        if !pasteboardItems.isEmpty {
            pasteboard.writeObjects(pasteboardItems)
        }
    }
}

// MARK: - Pure decision logic

/// A text range read from `kAXSelectedTextRangeAttribute` (UTF-16 units).
struct AXTextRange: Equatable, Sendable {
    var location: Int
    var length: Int
}

/// AX readings of the focused text element at one point in time.
/// `nil` fields mean the attribute could not be read.
struct AXTextReading: Equatable, Sendable {
    var characterCount: Int?
    var selectedRange: AXTextRange?

    static let unreadable = AXTextReading(characterCount: nil, selectedRange: nil)

    var isReadable: Bool {
        characterCount != nil || selectedRange != nil
    }
}

/// What to do with the clipboard once the insert finished.
enum ClipboardAction: Equatable, Sendable {
    /// Put the user's previous clipboard back.
    case restoreSnapshot
    /// Rewrite the transcript as a normal (non-transient) clipboard item.
    case keepTranscript
    /// Someone else wrote to the clipboard meanwhile; do not touch it.
    case leaveAlone
}

enum TextInsertionDecision {
    /// True when an attribute readable both before and after differs.
    /// Compares "changed", not "increased" (pasting over a selection can shrink text).
    static func didChange(before: AXTextReading, after: AXTextReading) -> Bool {
        if let beforeCount = before.characterCount,
           let afterCount = after.characterCount,
           beforeCount != afterCount {
            return true
        }

        if let beforeRange = before.selectedRange,
           let afterRange = after.selectedRange,
           beforeRange != afterRange {
            return true
        }

        return false
    }

    /// Classifies one verification poll. Returns `nil` to keep polling.
    /// - `before` unreadable → `.unknown` (verification unavailable).
    /// - change detected → `.confirmed`.
    /// - readable, unchanged and `timedOut` → `.failed(.pasteNotDetected)`.
    static func verificationResult(
        before: AXTextReading,
        after: AXTextReading,
        timedOut: Bool
    ) -> InsertResult? {
        guard before.isReadable else {
            return .unknown
        }

        if didChange(before: before, after: after) {
            return .confirmed
        }

        return timedOut ? .failed(.pasteNotDetected) : nil
    }

    /// Clipboard policy after the paste attempt. Only acts if the pasteboard
    /// still holds what we wrote (`currentChangeCount == writtenChangeCount`).
    static func clipboardAction(
        for result: InsertResult,
        currentChangeCount: Int,
        writtenChangeCount: Int
    ) -> ClipboardAction {
        guard currentChangeCount == writtenChangeCount else {
            return .leaveAlone
        }

        switch result {
        case .confirmed:
            return .restoreSnapshot
        case .failed, .unknown:
            return .keepTranscript
        }
    }
}

// MARK: - TextInserter

/// Pastes text into another app by writing it to the clipboard and
/// synthesizing ⌘V, then verifies the paste through Accessibility.
@MainActor
final class TextInserter {
    static let transientPasteboardType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let pasteboard: NSPasteboard

    /// How long to wait for the target app to become frontmost.
    private let activationTimeout: Duration = .milliseconds(500)
    private let activationPollInterval: Duration = .milliseconds(25)
    /// How long to watch the focused element for a change after ⌘V.
    private let verificationTimeout: Duration = .milliseconds(600)
    private let verificationPollInterval: Duration = .milliseconds(50)
    /// When verification is unavailable, give the target time to read the
    /// pasteboard before it is rewritten without the transient marker.
    private let unverifiableSettleDelay: Duration = .milliseconds(200)
    /// Cap for synchronous AX calls so an unresponsive app cannot block the UI.
    private let axMessagingTimeout: Float = 0.25

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func insert(_ text: String, into target: NSRunningApplication?) async -> InsertResult {
        let result = await performInsert(text, into: target)
        textInserterLog.info(
            "Insert finished: result=\(result.logName, privacy: .public) target=\(target?.bundleIdentifier ?? "nil", privacy: .public) length=\(text.count, privacy: .public)"
        )
        return result
    }

    private func performInsert(_ text: String, into requestedTarget: NSRunningApplication?) async -> InsertResult {
        // 1. Pre-checks. Any failure here still leaves the transcript on the
        //    clipboard as a normal item so the user can paste manually.
        guard AccessibilityPermission.isTrusted else {
            writeTranscript(text, transient: false)
            return .failed(.noAccessibilityPermission)
        }

        if IsSecureEventInputEnabled() {
            writeTranscript(text, transient: false)
            return .failed(.secureInputActive)
        }

        let target = requestedTarget ?? NSWorkspace.shared.frontmostApplication

        if let target {
            if target.isTerminated {
                writeTranscript(text, transient: false)
                return .failed(.targetAppTerminated)
            }

            if !(await activateIfNeeded(target)) {
                writeTranscript(text, transient: false)
                return .failed(target.isTerminated ? .targetAppTerminated : .targetActivationFailed)
            }
        }

        // 2. AX snapshot of the focused element before pasting.
        let appElement = target.map { makeApplicationElement(pid: $0.processIdentifier) }
        let before = appElement.map(readFocusedText(in:)) ?? .unreadable

        // 3. Snapshot the pasteboard and write the transcript (transient).
        let snapshot = PasteboardSnapshot(capturing: pasteboard)
        let writtenChangeCount = writeTranscript(text, transient: true)

        // 4. Synthesize ⌘V.
        guard postPasteShortcut() else {
            let result = InsertResult.failed(.eventPostFailed)
            applyClipboardPolicy(for: result, text: text, snapshot: snapshot, writtenChangeCount: writtenChangeCount)
            return result
        }

        // 5. Verify through AX.
        let result = await verifyPaste(in: appElement, before: before)

        // 6. Clipboard policy.
        applyClipboardPolicy(for: result, text: text, snapshot: snapshot, writtenChangeCount: writtenChangeCount)
        return result
    }

    // MARK: Activation

    private func activateIfNeeded(_ target: NSRunningApplication) async -> Bool {
        if isFrontmost(target) {
            return true
        }

        textInserterLog.info(
            "Activating target app before paste: \(target.bundleIdentifier ?? "unknown", privacy: .public)"
        )
        target.activate()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: activationTimeout)
        while clock.now < deadline {
            try? await Task.sleep(for: activationPollInterval)
            if target.isTerminated {
                return false
            }
            if isFrontmost(target) {
                return true
            }
        }

        return isFrontmost(target)
    }

    private func isFrontmost(_ target: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
    }

    // MARK: Verification

    private func verifyPaste(in appElement: AXUIElement?, before: AXTextReading) async -> InsertResult {
        guard let appElement, before.isReadable else {
            try? await Task.sleep(for: unverifiableSettleDelay)
            return .unknown
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: verificationTimeout)

        while true {
            try? await Task.sleep(for: verificationPollInterval)
            let timedOut = clock.now >= deadline || Task.isCancelled
            let after = readFocusedText(in: appElement)

            if let result = TextInsertionDecision.verificationResult(
                before: before,
                after: after,
                timedOut: timedOut
            ) {
                return result
            }
        }
    }

    // MARK: Clipboard

    @discardableResult
    private func writeTranscript(_ text: String, transient: Bool) -> Int {
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if transient {
            item.setData(Data(), forType: Self.transientPasteboardType)
        }
        pasteboard.writeObjects([item])

        return pasteboard.changeCount
    }

    private func applyClipboardPolicy(
        for result: InsertResult,
        text: String,
        snapshot: PasteboardSnapshot,
        writtenChangeCount: Int
    ) {
        let action = TextInsertionDecision.clipboardAction(
            for: result,
            currentChangeCount: pasteboard.changeCount,
            writtenChangeCount: writtenChangeCount
        )

        switch action {
        case .restoreSnapshot:
            snapshot.restore(to: pasteboard)
        case .keepTranscript:
            writeTranscript(text, transient: false)
        case .leaveAlone:
            textInserterLog.info("Clipboard changed during insert; leaving it untouched")
        }
    }

    // MARK: CGEvent

    private func postPasteShortcut() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_V)

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            textInserterLog.error("Failed to create ⌘V keyboard events")
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    // MARK: AX helpers

    private func makeApplicationElement(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, axMessagingTimeout)
        // Asks Chromium/Electron apps to build their AX tree. Errors are expected
        // for apps that do not support it. AXEnhancedUserInterface is
        // intentionally not set (it breaks window animations in some apps).
        _ = AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return element
    }

    private func readFocusedText(in appElement: AXUIElement) -> AXTextReading {
        guard let focused = focusedElement(in: appElement) else {
            return .unreadable
        }

        return AXTextReading(
            characterCount: characterCount(of: focused),
            selectedRange: selectedRange(of: focused)
        )
    }

    private func copyAttribute(_ attribute: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else {
            return nil
        }
        return value
    }

    private func focusedElement(in appElement: AXUIElement) -> AXUIElement? {
        guard
            let value = copyAttribute(kAXFocusedUIElementAttribute, of: appElement),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        let focused = value as! AXUIElement
        // The messaging timeout is per element; apply the cap here too so
        // reads on the focused element cannot block on a hung app.
        AXUIElementSetMessagingTimeout(focused, axMessagingTimeout)
        return focused
    }

    private func characterCount(of element: AXUIElement) -> Int? {
        if let value = copyAttribute(kAXNumberOfCharactersAttribute, of: element),
           CFGetTypeID(value) == CFNumberGetTypeID() {
            return (value as! NSNumber).intValue
        }

        // Fallback: length of the string value, in UTF-16 units like AX ranges.
        if let value = copyAttribute(kAXValueAttribute, of: element),
           CFGetTypeID(value) == CFStringGetTypeID() {
            return (value as! String).utf16.count
        }

        return nil
    }

    private func selectedRange(of element: AXUIElement) -> AXTextRange? {
        guard
            let value = copyAttribute(kAXSelectedTextRangeAttribute, of: element),
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }
        return AXTextRange(location: range.location, length: range.length)
    }
}
