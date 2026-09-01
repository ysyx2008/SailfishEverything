import Carbon
import Foundation
import SailfishEverythingCore

final class ToggleHotKey {
    var action: () -> Void = {}
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register(_ combo: AppHotKey) {
        unregister()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                Unmanaged<ToggleHotKey>.fromOpaque(userData).takeUnretainedValue().action()
                return noErr
            },
            1,
            &eventType,
            userInfo,
            &handlerRef
        )
        let identifier = EventHotKeyID(signature: OSType(0x53464556), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            combo.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit {
        unregister()
    }
}

extension AppHotKey {
    var carbonModifiers: UInt32 {
        switch self {
        case .controlSpace: return UInt32(controlKey)
        case .optionSpace: return UInt32(optionKey)
        case .commandShiftSpace: return UInt32(cmdKey | shiftKey)
        case .controlOptionSpace: return UInt32(controlKey | optionKey)
        }
    }

    var title: String {
        switch self {
        case .controlSpace: return L10n.t(.hotKeyControlSpace)
        case .optionSpace: return L10n.t(.hotKeyOptionSpace)
        case .commandShiftSpace: return L10n.t(.hotKeyCommandShiftSpace)
        case .controlOptionSpace: return L10n.t(.hotKeyControlOptionSpace)
        }
    }
}
