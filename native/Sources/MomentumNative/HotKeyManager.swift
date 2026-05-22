import Carbon
import Foundation

enum HotKeyError: LocalizedError {
    case installHandlerFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .installHandlerFailed(let status):
            return "Failed to install the global hotkey handler: \(status)"
        case .registrationFailed(let status):
            return "Failed to register the global hotkey: \(status)"
        }
    }
}

final class HotKeyManager {
    var onKeyDown: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func register() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return noErr
                }

                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onKeyDown?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            throw HotKeyError.installHandlerFailed(installStatus)
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D4F4D54), id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            throw HotKeyError.registrationFailed(registerStatus)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
