import Cocoa
import Carbon.HIToolbox

/// A global keyboard shortcut: one key plus optional modifiers.
struct Shortcut: Equatable {
    /// Virtual key code (the `kVK_…` constants).
    var keyCode: UInt32
    /// Carbon modifier mask (`cmdKey`, `optionKey`, `controlKey`, `shiftKey`).
    var modifiers: UInt32
}

/// F-keys are the only keys allowed as a shortcut without a modifier.
let functionKeyNames: [Int: String] = [
    kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
    kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
    kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
    kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
]

let specialKeyNames: [Int: String] = [
    kVK_Return: "Return", kVK_Tab: "Tab", kVK_Space: "Space", kVK_Delete: "Delete",
    kVK_ForwardDelete: "Fwd Delete", kVK_Escape: "Esc",
    kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
]

/// Converts the modifier flags of a key event into the Carbon mask that hot keys use.
func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var mask: UInt32 = 0
    if flags.contains(.command) { mask |= UInt32(cmdKey) }
    if flags.contains(.option) { mask |= UInt32(optionKey) }
    if flags.contains(.control) { mask |= UInt32(controlKey) }
    if flags.contains(.shift) { mask |= UInt32(shiftKey) }
    return mask
}

/// Human-readable form of a shortcut, for example "⌃⌥V" or "F4".
func shortcutLabel(_ shortcut: Shortcut) -> String {
    var text = ""
    if shortcut.modifiers & UInt32(controlKey) != 0 { text += "⌃" }
    if shortcut.modifiers & UInt32(optionKey) != 0 { text += "⌥" }
    if shortcut.modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
    if shortcut.modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
    let code = Int(shortcut.keyCode)
    if let name = functionKeyNames[code] {
        text += name
    } else if let name = specialKeyNames[code] {
        text += name
    } else if let key = usKeyTable.first(where: { $0.code == code }) {
        text += String(key.plain).uppercased()
    } else {
        text += "Key \(code)"
    }
    return text
}
