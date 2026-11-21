import Carbon.HIToolbox
import Foundation

/// 전역 단축키. Carbon API를 써서 손쉬운 사용 권한 없이도 동작해요.
final class HotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false
    private static var nextID: UInt32 = 1

    private var ref: EventHotKeyRef?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        HotKey.installHandlerIfNeeded()
        let id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.actions[id] = action

        let hotKeyID = EventHotKeyID(signature: OSType(0x53544B54), id: id) // 'STKT'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr, let action = HotKey.actions[hotKeyID.id] {
                DispatchQueue.main.async { action() }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
