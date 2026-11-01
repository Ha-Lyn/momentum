import Carbon
import Foundation
import os

private let hotKeyLog = Logger(subsystem: "com.momentum.native", category: "hotkey")

enum HotKeyError: LocalizedError {
    case installHandlerFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .installHandlerFailed(let status):
            return "Failed to install the global hotkey handler: \(status)"
        case .registrationFailed(let status):
            if status == OSStatus(eventHotKeyExistsErr) {
                return "The global hotkey is already in use by another app."
            }
            return "Failed to register the global hotkey: \(status)"
        }
    }
}

/// Registers multiple global hotkeys through Carbon, with pressed and
/// (optionally) released callbacks. A single application event handler
/// dispatches both event kinds by `EventHotKeyID`.
@MainActor
final class HotKeyManager {
    /// Hotkey ids used by the app.
    static let noteToggleID: UInt32 = 1
    static let pushToTalkID: UInt32 = 2

    /// 'MOMT'
    private nonisolated static let signature = OSType(0x4D4F4D54)

    private struct Registration {
        let ref: EventHotKeyRef
        let onPress: @MainActor () -> Void
        let onRelease: (@MainActor () -> Void)?
    }

    private var registrations: [UInt32: Registration] = [:]
    private var eventHandlerRef: EventHandlerRef?

    /// Registers (or replaces) the hotkey with `id`.
    /// - Parameters:
    ///   - keyCode: Carbon virtual key code (`kVK_*`).
    ///   - modifiers: Carbon modifier mask (`cmdKey | shiftKey`, ...).
    func register(
        id: UInt32,
        keyCode: UInt32,
        modifiers: UInt32,
        onPress: @escaping @MainActor () -> Void,
        onRelease: (@MainActor () -> Void)? = nil
    ) throws {
        try installHandlerIfNeeded()
        unregister(id: id)

        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            throw HotKeyError.registrationFailed(status)
        }

        registrations[id] = Registration(ref: hotKeyRef, onPress: onPress, onRelease: onRelease)
    }

    func unregister(id: UInt32) {
        guard let registration = registrations.removeValue(forKey: id) else {
            return
        }
        UnregisterEventHotKey(registration.ref)
    }

    /// Unregisters every hotkey and removes the event handler.
    func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func installHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else {
            return
        }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard parameterStatus == noErr, hotKeyID.signature == HotKeyManager.signature else {
                    return OSStatus(eventNotHandledErr)
                }

                let isPressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                let id = hotKeyID.id
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

                // Handlers on the application event target run on the main thread.
                return MainActor.assumeIsolated {
                    manager.dispatch(id: id, isPressed: isPressed) ? noErr : OSStatus(eventNotHandledErr)
                }
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard status == noErr else {
            eventHandlerRef = nil
            throw HotKeyError.installHandlerFailed(status)
        }
    }

    private func dispatch(id: UInt32, isPressed: Bool) -> Bool {
        guard let registration = registrations[id] else {
            hotKeyLog.debug("Ignoring event for unregistered hotkey id \(id, privacy: .public)")
            return false
        }

        if isPressed {
            registration.onPress()
        } else {
            registration.onRelease?()
        }
        return true
    }
}
