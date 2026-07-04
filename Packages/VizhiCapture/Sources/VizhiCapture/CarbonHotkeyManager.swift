import AppKit
import Carbon.HIToolbox

/// Registers system-wide hotkeys via Carbon's `RegisterEventHotKey`. This works for a menubar
/// `.accessory` app and, unlike `NSEvent` global monitors, needs no Accessibility/Input-Monitoring
/// permission and properly claims the shortcut. Invokes `onTrigger` on the main actor when a
/// registered hotkey is pressed.
@MainActor
public final class CarbonHotkeyManager {
    /// Called with the action bound to the pressed hotkey.
    public var onTrigger: ((CaptureAction) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var actionsByID: [UInt32: CaptureAction] = [:]
    private var handlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1

    /// Four-char signature 'VZHK' identifying our hotkeys.
    private let signature: OSType = 0x565A_484B

    public init() {}

    /// Replaces any existing registrations with the given set. Shortcuts the system already owns
    /// (e.g. ⇧⌘3) fail to register and are skipped.
    public func register(_ hotkeys: [CaptureAction: Hotkey]) {
        unregisterAll()
        installHandlerIfNeeded()
        for (action, hotkey) in hotkeys {
            let id = nextID
            nextID += 1
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: signature, id: id)
            let status = RegisterEventHotKey(
                UInt32(hotkey.keyCode),
                Self.carbonModifiers(hotkey.modifiers),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr {
                actionsByID[id] = action
                hotKeyRefs.append(ref)
            }
        }
    }

    public func unregisterAll() {
        for ref in hotKeyRefs where ref != nil {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        actionsByID.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotkeyEventHandlerUPP, 1, &eventType, selfPtr, &handlerRef)
    }

    fileprivate func handle(id: UInt32) {
        guard let action = actionsByID[id] else { return }
        onTrigger?(action)
    }

    /// Maps our modifier set to a Carbon modifier mask. Pure, for unit testing.
    nonisolated static func carbonModifiers(_ modifiers: HotkeyModifiers) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}

/// C event handler trampoline. Carbon hotkey events arrive on the main run loop, so hopping with
/// `assumeIsolated` is sound. Looks up the manager passed as `userData` and forwards the hotkey id.
private func hotkeyEventHandlerUPP(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
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
    guard status == noErr else { return status }

    let manager = Unmanaged<CarbonHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    let id = hotKeyID.id
    MainActor.assumeIsolated {
        manager.handle(id: id)
    }
    return noErr
}
