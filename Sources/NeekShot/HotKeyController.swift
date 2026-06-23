import Carbon.HIToolbox
import Foundation

enum HotKeyError: LocalizedError {
    case installHandlerFailed(OSStatus)
    case registerFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .installHandlerFailed(let status):
            "Could not install the hotkey handler. OSStatus \(status)."
        case .registerFailed(let status):
            "Could not register the hotkey. OSStatus \(status)."
        }
    }
}

final class HotKeyController: @unchecked Sendable {
    static let defaultShortcutDescription = "Control + Option + Command + S"

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var handler: (() -> Void)?

    deinit {
        unregister()
    }

    func registerDefault(handler: @escaping () -> Void) throws {
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else {
                return noErr
            }

            let controller = Unmanaged<HotKeyController>
                .fromOpaque(userData)
                .takeUnretainedValue()

            controller.handler?()
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            throw HotKeyError.installHandlerFailed(installStatus)
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4E53484B), id: 1)
        let modifiers = UInt32(cmdKey | optionKey | controlKey)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_S),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            throw HotKeyError.registerFailed(registerStatus)
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
