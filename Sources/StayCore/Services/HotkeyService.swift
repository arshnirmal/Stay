import Foundation
import Carbon

private func carbonHotkeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = userData else { return noErr }
    let action = Unmanaged<AnyObject>.fromOpaque(userData).takeUnretainedValue() as! (@Sendable () -> Void)
    action()
    return noErr
}

public final class HotkeyService: @unchecked Sendable {
    public static let shared = HotkeyService()
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actionBoxes: [Unmanaged<AnyObject>] = []

    private init() {}

    public func register(keyCode: UInt32, modifiers: UInt32, action: @escaping @Sendable () -> Void) -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let box = Unmanaged.passRetained(action as AnyObject)
        actionBoxes.append(box)

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyHandler,
            1,
            &eventType,
            box.toOpaque(),
            nil
        )
        guard status == noErr else { return false }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x53544159), id: UInt32(hotKeyRefs.count + 1)) // 'STAY'
        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard regStatus == noErr, let ref = hotKeyRef else { return false }
        hotKeyRefs.append(ref)
        return true
    }

    public func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        for box in actionBoxes {
            box.release()
        }
        actionBoxes.removeAll()
    }

    deinit {
        unregisterAll()
    }
}
