import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(),
                            hotKeyEventHandler,
                            1,
                            &eventSpec,
                            selfPtr,
                            &handlerRef)
        if installStatus != noErr { NSLog("Sift: InstallEventHandler failed (\(installStatus))") }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("LNCH"), id: 1)
        let registerStatus = RegisterEventHotKey(UInt32(kVK_Space),
                            UInt32(cmdKey),
                            hotKeyID,
                            GetApplicationEventTarget(),
                            0,
                            &hotKeyRef)
        if registerStatus != noErr { NSLog("Sift: RegisterEventHotKey failed (\(registerStatus)) — is Cmd-Space still bound to Spotlight?") }
    }

    func fire() { onTrigger?() }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

private func hotKeyEventHandler(_ next: EventHandlerCallRef?,
                                _ event: EventRef?,
                                _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return noErr }
    Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue().fire()
    return noErr
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for unit in string.utf16 { result = (result << 8) + OSType(unit) }
    return result
}
