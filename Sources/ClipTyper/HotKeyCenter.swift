import Carbon.HIToolbox

/// Registers system-wide keyboard shortcuts.
///
/// Uses Carbon hot keys because they need no extra permission and they swallow the key
/// combination, so it does not also reach the app (or remote session) in front.
/// Several shortcuts can be active at once, each under its own numeric id.
final class HotKeyCenter {
    private var handlers: [UInt32: () -> Void] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private let signature = OSType(0x434C_5459)   // 'CLTY'

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        // One C callback receives every hot key press; the id inside the event says which one.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event = event, let userData = userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           UInt32(kEventParamDirectObject),
                                           UInt32(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return status }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            center.fire(hotKeyID.id)
            return noErr
        }, 1, &spec, pointer, &eventHandler)
    }

    /// Registers (or replaces) the shortcut with this id. Returns false if the system refused,
    /// which usually means another app already owns that key combination.
    @discardableResult
    func register(id: UInt32, shortcut: Shortcut, handler: @escaping () -> Void) -> Bool {
        unregister(id: id)
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let registered = reference else { return false }
        references[id] = registered
        handlers[id] = handler
        return true
    }

    func unregister(id: UInt32) {
        if let reference = references.removeValue(forKey: id) {
            UnregisterEventHotKey(reference)
        }
        handlers[id] = nil
    }

    private func fire(_ id: UInt32) {
        handlers[id]?()
    }
}
