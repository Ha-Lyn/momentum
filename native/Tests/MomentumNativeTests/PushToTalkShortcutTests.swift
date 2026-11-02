import AppKit
import Carbon
import Foundation
import Testing
@testable import MomentumNative

@Suite("PushToTalkShortcut")
struct PushToTalkShortcutTests {
    private static let space = UInt32(kVK_Space)

    // MARK: Default

    @Test func defaultIsOptionShiftModifierOnly() {
        let shortcut = PushToTalkShortcut.default
        #expect(shortcut.modifiers == [.option, .shift])
        #expect(shortcut.keyCode == nil)
        #expect(shortcut.isModifierOnly)
        #expect(shortcut.validate() == nil)
    }

    // MARK: Display

    @Test func displayStringModifierOnly() {
        #expect(PushToTalkShortcut.default.displayString == "⌥⇧")
    }

    @Test func displayStringWithKey() {
        let shortcut = PushToTalkShortcut(modifiers: [.control, .option], keyCode: Self.space)
        #expect(shortcut.displayString == "⌃⌥Space")
        #expect(!shortcut.isModifierOnly)
    }

    @Test func displayStringUsesMacOSModifierOrder() {
        // Insertion order must not matter.
        let modifiers: PushToTalkShortcut.ModifierSet = [.command, .shift, .option, .control]
        #expect(modifiers.displayString == "⌃⌥⇧⌘")
        #expect(PushToTalkShortcut(modifiers: [.command, .control], keyCode: UInt32(kVK_ANSI_K)).displayString == "⌃⌘K")
    }

    @Test func unknownKeyCodeHasFallbackName() {
        #expect(PushToTalkShortcut.keyName(for: 0xFFFF) == "Key 65535")
        #expect(PushToTalkShortcut.keyName(for: UInt32(kVK_F5)) == "F5")
    }

    // MARK: Validation

    @Test(arguments: [nil, UInt32(kVK_Space)])
    func noModifiersIsInvalid(keyCode: UInt32?) {
        #expect(PushToTalkShortcut(modifiers: [], keyCode: keyCode).validate() == .noModifiers)
    }

    @Test func noteToggleHotkeyConflicts() {
        #expect(PushToTalkShortcut(modifiers: [.command, .shift], keyCode: Self.space).validate() == .conflictsWithNoteToggle)
        #expect(PushToTalkShortcut.noteToggle.validate() == .conflictsWithNoteToggle)
    }

    @Test func modifierOnlyOnNoteToggleModifiersConflicts() {
        #expect(PushToTalkShortcut(modifiers: [.command, .shift], keyCode: nil).validate() == .conflictsWithNoteToggle)
    }

    @Test func noteToggleModifiersWithOtherKeyIsValid() {
        #expect(PushToTalkShortcut(modifiers: [.command, .shift], keyCode: UInt32(kVK_ANSI_K)).validate() == nil)
    }

    @Test func controlOptionSpaceIsValid() {
        #expect(PushToTalkShortcut(modifiers: [.control, .option], keyCode: Self.space).validate() == nil)
    }

    @Test(arguments: [
        PushToTalkShortcut.ModifierSet.control,
        .option,
        .shift,
        .command,
    ])
    func singleModifierIsValid(modifier: PushToTalkShortcut.ModifierSet) {
        #expect(PushToTalkShortcut(modifiers: modifier, keyCode: nil).validate() == nil)
        let expectedWithKey: PushToTalkShortcut.ValidationError? = modifier == .command ? .conflictsWithSystemShortcut : nil
        #expect(PushToTalkShortcut(modifiers: modifier, keyCode: Self.space).validate() == expectedWithKey)
    }

    @Test(arguments: [kVK_ANSI_V, kVK_ANSI_C, kVK_ANSI_Q])
    func commandOnlyWithKeyIsRejected(keyCode: Int) {
        #expect(
            PushToTalkShortcut(modifiers: [.command], keyCode: UInt32(keyCode)).validate()
                == .conflictsWithSystemShortcut
        )
    }

    @Test func commandWithAnotherModifierAndVIsValid() {
        #expect(PushToTalkShortcut(modifiers: [.command, .option], keyCode: UInt32(kVK_ANSI_V)).validate() == nil)
    }

    // MARK: Persistence

    @Test func loadWithoutSavedValueReturnsDefault() {
        withIsolatedDefaults { defaults in
            #expect(PushToTalkShortcut.load(from: defaults) == .default)
        }
    }

    @Test(arguments: [
        PushToTalkShortcut(modifiers: [.control, .option], keyCode: UInt32(kVK_Space)),
        PushToTalkShortcut(modifiers: [.command], keyCode: nil),
        PushToTalkShortcut(modifiers: .all, keyCode: UInt32(kVK_F13)),
        PushToTalkShortcut.default,
    ])
    func persistAndLoadRoundTrip(shortcut: PushToTalkShortcut) {
        withIsolatedDefaults { defaults in
            shortcut.persist(to: defaults)
            #expect(defaults.data(forKey: PushToTalkShortcut.defaultsKey) != nil)
            #expect(PushToTalkShortcut.load(from: defaults) == shortcut)
        }
    }

    @Test func loadFallsBackOnUndecodableData() {
        withIsolatedDefaults { defaults in
            defaults.set(Data("not json".utf8), forKey: PushToTalkShortcut.defaultsKey)
            #expect(PushToTalkShortcut.load(from: defaults) == .default)
        }
    }

    @Test func loadFallsBackOnWrongValueType() {
        withIsolatedDefaults { defaults in
            defaults.set("⌥⇧", forKey: PushToTalkShortcut.defaultsKey)
            #expect(PushToTalkShortcut.load(from: defaults) == .default)
        }
    }

    @Test(arguments: [
        PushToTalkShortcut(modifiers: [], keyCode: UInt32(kVK_Space)),
        PushToTalkShortcut(modifiers: [.command, .shift], keyCode: UInt32(kVK_Space)),
        PushToTalkShortcut(modifiers: [.command, .shift], keyCode: nil),
    ])
    func loadFallsBackOnInvalidSavedShortcut(shortcut: PushToTalkShortcut) {
        withIsolatedDefaults { defaults in
            shortcut.persist(to: defaults)
            #expect(PushToTalkShortcut.load(from: defaults) == .default)
        }
    }

    // MARK: ModifierSet

    @Test func modifierSetFromEventFlagsIgnoresNonModifierFlags() {
        let flags: NSEvent.ModifierFlags = [.option, .shift, .capsLock, .function, .numericPad, .help]
        #expect(PushToTalkShortcut.ModifierSet(eventFlags: flags) == [.option, .shift])
    }

    @Test func modifierSetFromOnlyIgnoredFlagsIsEmpty() {
        let flags: NSEvent.ModifierFlags = [.capsLock, .function, .numericPad]
        #expect(PushToTalkShortcut.ModifierSet(eventFlags: flags).isEmpty)
    }

    @Test func modifierSetIgnoresDeviceDependentSideBits() {
        // NX_DEVICELALTKEYMASK (0x20) | NX_DEVICELSHIFTKEYMASK (0x02) alongside the device-independent flags.
        let flags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags([.option, .shift]).rawValue | 0x20 | 0x02)
        #expect(PushToTalkShortcut.ModifierSet(eventFlags: flags) == [.option, .shift])
    }

    @Test func modifierSetEventFlagsRoundTrip() {
        let all = PushToTalkShortcut.ModifierSet.all
        #expect(all.eventFlags == [.control, .option, .shift, .command])
        #expect(PushToTalkShortcut.ModifierSet(eventFlags: all.eventFlags) == all)
        let none: PushToTalkShortcut.ModifierSet = []
        #expect(none.eventFlags.isEmpty)
    }

    @Test func carbonFlagsMapping() {
        typealias Mods = PushToTalkShortcut.ModifierSet
        let none: Mods = []
        let controlOption: Mods = [.control, .option]
        #expect(Mods.control.carbonFlags == UInt32(controlKey))
        #expect(Mods.option.carbonFlags == UInt32(optionKey))
        #expect(Mods.shift.carbonFlags == UInt32(shiftKey))
        #expect(Mods.command.carbonFlags == UInt32(cmdKey))
        #expect(none.carbonFlags == 0)
        #expect(controlOption.carbonFlags == UInt32(controlKey | optionKey))
        #expect(Mods.all.carbonFlags == UInt32(controlKey | optionKey | shiftKey | cmdKey))
    }
}

@Suite("QuickTranscribeSettings")
struct QuickTranscribeSettingsTests {
    @Test func defaultsToEnabled() {
        withIsolatedDefaults { defaults in
            #expect(QuickTranscribeSettings.isEnabled(in: defaults))
        }
    }

    @Test func persistsDisabledAndEnabled() {
        withIsolatedDefaults { defaults in
            QuickTranscribeSettings.setEnabled(false, in: defaults)
            #expect(!QuickTranscribeSettings.isEnabled(in: defaults))
            #expect(defaults.object(forKey: QuickTranscribeSettings.enabledKey) as? Bool == false)

            QuickTranscribeSettings.setEnabled(true, in: defaults)
            #expect(QuickTranscribeSettings.isEnabled(in: defaults))
        }
    }

    @Test func nonBoolValueFallsBackToEnabled() {
        withIsolatedDefaults { defaults in
            defaults.set("nope", forKey: QuickTranscribeSettings.enabledKey)
            #expect(QuickTranscribeSettings.isEnabled(in: defaults))
        }
    }
}
