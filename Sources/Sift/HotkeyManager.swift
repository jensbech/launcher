import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    struct Binding {
        let keyCode: UInt32
        let modifiers: UInt32
        let id: UInt32
        let label: String
        let action: () -> Void
    }

    private var bindings: [UInt32: Binding] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = fourCharCode("LNCH")

    func register(_ binding: Binding) {
        bindings[binding.id] = binding
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: binding.id)
        let status = RegisterEventHotKey(binding.keyCode,
                                         binding.modifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status != noErr {
            NSLog("Sift: RegisterEventHotKey failed for \(binding.label) (\(status))")
        }
        if let ref { hotKeyRefs.append(ref) }
    }

    fileprivate func fire(id: UInt32) {
        bindings[id]?.action()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(),
                                         hotKeyEventHandler,
                                         1,
                                         &eventSpec,
                                         selfPtr,
                                         &handlerRef)
        if status != noErr {
            NSLog("Sift: InstallEventHandler failed (\(status))")
        }
    }

    deinit {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

private func hotKeyEventHandler(_ next: EventHandlerCallRef?,
                                _ event: EventRef?,
                                _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData, let event else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    if status != noErr { return noErr }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.fire(id: hotKeyID.id)
    return noErr
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for unit in string.utf16 { result = (result << 8) + OSType(unit) }
    return result
}
