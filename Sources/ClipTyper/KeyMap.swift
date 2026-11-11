import CoreGraphics
import Carbon.HIToolbox

/// The US ANSI keyboard: each physical key with the character it produces alone and with Shift.
///
/// "Key presses" mode sends these physical keys. The remote machine turns them back into
/// characters using its own layout, which is why that layout has to be English (US).
let usKeyTable: [(code: Int, plain: Character, shifted: Character)] = [
    (kVK_ANSI_A, "a", "A"), (kVK_ANSI_B, "b", "B"), (kVK_ANSI_C, "c", "C"),
    (kVK_ANSI_D, "d", "D"), (kVK_ANSI_E, "e", "E"), (kVK_ANSI_F, "f", "F"),
    (kVK_ANSI_G, "g", "G"), (kVK_ANSI_H, "h", "H"), (kVK_ANSI_I, "i", "I"),
    (kVK_ANSI_J, "j", "J"), (kVK_ANSI_K, "k", "K"), (kVK_ANSI_L, "l", "L"),
    (kVK_ANSI_M, "m", "M"), (kVK_ANSI_N, "n", "N"), (kVK_ANSI_O, "o", "O"),
    (kVK_ANSI_P, "p", "P"), (kVK_ANSI_Q, "q", "Q"), (kVK_ANSI_R, "r", "R"),
    (kVK_ANSI_S, "s", "S"), (kVK_ANSI_T, "t", "T"), (kVK_ANSI_U, "u", "U"),
    (kVK_ANSI_V, "v", "V"), (kVK_ANSI_W, "w", "W"), (kVK_ANSI_X, "x", "X"),
    (kVK_ANSI_Y, "y", "Y"), (kVK_ANSI_Z, "z", "Z"),
    (kVK_ANSI_1, "1", "!"), (kVK_ANSI_2, "2", "@"), (kVK_ANSI_3, "3", "#"),
    (kVK_ANSI_4, "4", "$"), (kVK_ANSI_5, "5", "%"), (kVK_ANSI_6, "6", "^"),
    (kVK_ANSI_7, "7", "&"), (kVK_ANSI_8, "8", "*"), (kVK_ANSI_9, "9", "("),
    (kVK_ANSI_0, "0", ")"),
    (kVK_ANSI_Minus, "-", "_"), (kVK_ANSI_Equal, "=", "+"),
    (kVK_ANSI_LeftBracket, "[", "{"), (kVK_ANSI_RightBracket, "]", "}"),
    (kVK_ANSI_Backslash, "\\", "|"), (kVK_ANSI_Semicolon, ";", ":"),
    (kVK_ANSI_Quote, "'", "\""), (kVK_ANSI_Comma, ",", "<"),
    (kVK_ANSI_Period, ".", ">"), (kVK_ANSI_Slash, "/", "?"),
    (kVK_ANSI_Grave, "`", "~"),
]

/// Lookup from a character to the key that types it, and whether Shift must be held.
/// Covers every printable ASCII character. Return and Tab are handled separately by the typer.
let usKeyMap: [Character: (code: CGKeyCode, shift: Bool)] = {
    var map: [Character: (code: CGKeyCode, shift: Bool)] = [:]
    map[" "] = (CGKeyCode(kVK_Space), false)
    for key in usKeyTable {
        map[key.plain] = (CGKeyCode(key.code), false)
        map[key.shifted] = (CGKeyCode(key.code), true)
    }
    return map
}()

/// Characters that often sneak into scripts copied from web pages, mail or Word.
/// They have no key on a US keyboard, so in "Key presses" mode they are swapped for the
/// plain form before typing (curly quotes, long dashes, non-breaking space, ellipsis).
let typographicReplacements: [(String, String)] = [
    ("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201C}", "\""), ("\u{201D}", "\""),
    ("\u{2013}", "-"), ("\u{2014}", "-"), ("\u{00A0}", " "), ("\u{2026}", "..."),
]
