import XCTest
import Carbon.HIToolbox
@testable import ClipTyper

final class KeyMapTests: XCTestCase {
    func testEveryPrintableASCIICharacterHasAKey() {
        for value in 0x20...0x7E {
            let character = Character(UnicodeScalar(UInt8(value)))
            XCTAssertNotNil(usKeyMap[character], "No key for \"\(character)\"")
        }
    }

    func testMapHoldsExactlyThePrintableASCIICharacters() {
        // 47 keys with two characters each, plus Space. A duplicate in the table would
        // overwrite another entry and make this count come up short.
        XCTAssertEqual(usKeyTable.count, 47)
        XCTAssertEqual(usKeyMap.count, 95)
    }

    func testNoPhysicalKeyIsListedTwice() {
        let codes = usKeyTable.map { $0.code }
        XCTAssertEqual(Set(codes).count, codes.count)
    }

    func testLettersUseShiftOnlyForCapitals() {
        XCTAssertEqual(usKeyMap["a"]?.code, CGKeyCode(kVK_ANSI_A))
        XCTAssertEqual(usKeyMap["a"]?.shift, false)
        XCTAssertEqual(usKeyMap["A"]?.code, CGKeyCode(kVK_ANSI_A))
        XCTAssertEqual(usKeyMap["A"]?.shift, true)
    }

    func testSymbolsThatMatterInScripts() {
        // Each pair shares one physical key; the second needs Shift.
        let pairs: [(Character, Character, Int)] = [
            ("4", "$", kVK_ANSI_4), ("9", "(", kVK_ANSI_9), ("0", ")", kVK_ANSI_0),
            (";", ":", kVK_ANSI_Semicolon), ("'", "\"", kVK_ANSI_Quote),
            ("\\", "|", kVK_ANSI_Backslash), ("[", "{", kVK_ANSI_LeftBracket),
            ("-", "_", kVK_ANSI_Minus), ("`", "~", kVK_ANSI_Grave),
        ]
        for (plain, shifted, code) in pairs {
            XCTAssertEqual(usKeyMap[plain]?.code, CGKeyCode(code))
            XCTAssertEqual(usKeyMap[plain]?.shift, false, "\(plain) should not need Shift")
            XCTAssertEqual(usKeyMap[shifted]?.code, CGKeyCode(code))
            XCTAssertEqual(usKeyMap[shifted]?.shift, true, "\(shifted) should need Shift")
        }
    }

    func testCharactersOutsideTheUSLayoutHaveNoKey() {
        XCTAssertNil(usKeyMap["я"])
        XCTAssertNil(usKeyMap["é"])
        XCTAssertNil(usKeyMap["→"])
    }

    func testShortcutLabels() {
        let controlOptionV = Shortcut(keyCode: UInt32(kVK_ANSI_V),
                                      modifiers: UInt32(controlKey | optionKey))
        XCTAssertEqual(shortcutLabel(controlOptionV), "⌃⌥V")
        XCTAssertEqual(shortcutLabel(Shortcut(keyCode: UInt32(kVK_F4), modifiers: 0)), "F4")
        let commandShiftReturn = Shortcut(keyCode: UInt32(kVK_Return),
                                          modifiers: UInt32(cmdKey | shiftKey))
        XCTAssertEqual(shortcutLabel(commandShiftReturn), "⇧⌘Return")
    }
}
