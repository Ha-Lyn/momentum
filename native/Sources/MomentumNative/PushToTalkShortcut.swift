import AppKit
import Carbon
import Foundation
import os

private let shortcutLog = Logger(subsystem: "com.momentum.native", category: "quick-transcribe")

/// The push-to-talk shortcut for Quick Transcribe: a set of modifiers plus an
/// optional key. `keyCode == nil` means a modifier-only shortcut (e.g. ⌥⇧),
/// detected through modifier-flag monitoring; otherwise it is a regular
/// hotkey (e.g. ⌃⌥Space) registered through Carbon.
struct PushToTalkShortcut: Equatable, Codable, Sendable {
    /// Device-independent modifier set with a stable, Codable raw value.
    struct ModifierSet: OptionSet, Codable, Hashable, Sendable {
        let rawValue: UInt

        init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        static let control = ModifierSet(rawValue: 1 << 0)
        static let option = ModifierSet(rawValue: 1 << 1)
        static let shift = ModifierSet(rawValue: 1 << 2)
        static let command = ModifierSet(rawValue: 1 << 3)

        /// All supported modifiers, in macOS display order (⌃⌥⇧⌘).
        static let all: ModifierSet = [.control, .option, .shift, .command]

        /// The `NSEvent.ModifierFlags` this set is compared against.
        static let relevantEventFlags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

        /// Builds a set from event flags, ignoring Caps Lock, Fn, numeric
        /// pad and side (left/right) information.
        init(eventFlags: NSEvent.ModifierFlags) {
            let flags = eventFlags.intersection(Self.relevantEventFlags)
            var set: ModifierSet = []
            if flags.contains(.control) { set.insert(.control) }
            if flags.contains(.option) { set.insert(.option) }
            if flags.contains(.shift) { set.insert(.shift) }
            if flags.contains(.command) { set.insert(.command) }
            self = set
        }

        var eventFlags: NSEvent.ModifierFlags {
            var flags: NSEvent.ModifierFlags = []
            if contains(.control) { flags.insert(.control) }
            if contains(.option) { flags.insert(.option) }
            if contains(.shift) { flags.insert(.shift) }
            if contains(.command) { flags.insert(.command) }
            return flags
        }

        /// Carbon modifier mask for `RegisterEventHotKey`.
        var carbonFlags: UInt32 {
            var flags: UInt32 = 0
            if contains(.control) { flags |= UInt32(controlKey) }
            if contains(.option) { flags |= UInt32(optionKey) }
            if contains(.shift) { flags |= UInt32(shiftKey) }
            if contains(.command) { flags |= UInt32(cmdKey) }
            return flags
        }

        /// Symbols in macOS order: ⌃⌥⇧⌘.
        var displayString: String {
            var result = ""
            if contains(.control) { result += "⌃" }
            if contains(.option) { result += "⌥" }
            if contains(.shift) { result += "⇧" }
            if contains(.command) { result += "⌘" }
            return result
        }
    }

    enum ValidationError: LocalizedError, Equatable, Sendable {
        case noModifiers
        case conflictsWithNoteToggle
        case conflictsWithSystemShortcut

        var errorDescription: String? {
            switch self {
            case .noModifiers:
                return "The shortcut must include at least one modifier key (⌃, ⌥, ⇧ or ⌘)."
            case .conflictsWithNoteToggle:
                return "This shortcut conflicts with the note recording shortcut (\(PushToTalkShortcut.noteToggle.displayString))."
            case .conflictsWithSystemShortcut:
                return "⌘ + key shortcuts are reserved by apps (for example ⌘V, which Quick Transcribe uses to paste). Add another modifier."
            }
        }
    }

    static let defaultsKey = "momentum.quickTranscribe.shortcut"

    /// ⌥⇧, modifier-only.
    static let `default` = PushToTalkShortcut(modifiers: [.option, .shift], keyCode: nil)

    /// The existing note recording toggle (⌘⇧Space), registered as hotkey id 1.
    static let noteToggle = PushToTalkShortcut(modifiers: [.command, .shift], keyCode: UInt32(kVK_Space))

    var modifiers: ModifierSet
    /// Carbon virtual key code (`kVK_*`); `nil` for a modifier-only shortcut.
    var keyCode: UInt32?

    init(modifiers: ModifierSet, keyCode: UInt32?) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    var isModifierOnly: Bool {
        keyCode == nil
    }

    /// e.g. "⌥⇧", "⌃⌥Space".
    var displayString: String {
        modifiers.displayString + (keyCode.map(Self.keyName(for:)) ?? "")
    }

    func validate() -> ValidationError? {
        if modifiers.isDisjoint(with: .all) {
            return .noModifiers
        }

        // A ⌘-only hotkey is a standard app shortcut (⌘C, ⌘Q, ...). The Carbon
        // hotkey would swallow it system-wide, and ⌘V would even intercept the
        // synthesized paste.
        if keyCode != nil, modifiers == .command {
            return .conflictsWithSystemShortcut
        }

        let toggle = Self.noteToggle
        if modifiers == toggle.modifiers {
            // Same hotkey, or modifier-only on the toggle's own modifiers
            // (every ⌘⇧Space press would arm push-to-talk first).
            if keyCode == toggle.keyCode || keyCode == nil {
                return .conflictsWithNoteToggle
            }
        }

        return nil
    }

    // MARK: Persistence

    /// Loads the saved shortcut, falling back to `.default` when missing,
    /// undecodable or invalid.
    static func load(from defaults: UserDefaults = .standard) -> PushToTalkShortcut {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return .default
        }

        do {
            let shortcut = try JSONDecoder().decode(PushToTalkShortcut.self, from: data)
            if let error = shortcut.validate() {
                shortcutLog.warning("Saved Quick Transcribe shortcut is invalid (\(String(describing: error), privacy: .public)); using default")
                return .default
            }
            return shortcut
        } catch {
            shortcutLog.warning("Failed to decode saved Quick Transcribe shortcut: \(error.localizedDescription, privacy: .public); using default")
            return .default
        }
    }

    func persist(to defaults: UserDefaults = .standard) {
        do {
            let data = try JSONEncoder().encode(self)
            defaults.set(data, forKey: Self.defaultsKey)
        } catch {
            shortcutLog.error("Failed to encode Quick Transcribe shortcut: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Key names

    /// Human-readable name for a Carbon virtual key code (ANSI layout).
    static func keyName(for keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyNames: [UInt32: String] = {
        let names: [Int: String] = [
            kVK_Space: "Space",
            kVK_Return: "Return",
            kVK_Tab: "Tab",
            kVK_Escape: "Escape",
            kVK_Delete: "Delete",
            kVK_ForwardDelete: "Forward Delete",
            kVK_Home: "Home",
            kVK_End: "End",
            kVK_PageUp: "Page Up",
            kVK_PageDown: "Page Down",
            kVK_LeftArrow: "←",
            kVK_RightArrow: "→",
            kVK_UpArrow: "↑",
            kVK_DownArrow: "↓",
            kVK_ANSI_KeypadEnter: "Enter",

            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
            kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",

            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",

            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",

            kVK_ANSI_Minus: "-",
            kVK_ANSI_Equal: "=",
            kVK_ANSI_LeftBracket: "[",
            kVK_ANSI_RightBracket: "]",
            kVK_ANSI_Semicolon: ";",
            kVK_ANSI_Quote: "'",
            kVK_ANSI_Comma: ",",
            kVK_ANSI_Period: ".",
            kVK_ANSI_Slash: "/",
            kVK_ANSI_Backslash: "\\",
            kVK_ANSI_Grave: "`",
        ]

        return Dictionary(uniqueKeysWithValues: names.map { (UInt32($0.key), $0.value) })
    }()
}

/// Quick Transcribe on/off switch (default: on).
enum QuickTranscribeSettings {
    static let enabledKey = "momentum.quickTranscribe.enabled"

    static var isEnabled: Bool {
        get { isEnabled(in: .standard) }
        set { setEnabled(newValue, in: .standard) }
    }

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults) {
        defaults.set(enabled, forKey: enabledKey)
    }
}
