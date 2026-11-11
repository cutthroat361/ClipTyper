import XCTest
@testable import ClipTyper

final class TextPreparationTests: XCTestCase {
    private func prepare(_ text: String, mode: TypingMode = .keyCodes,
                         tabsToSpaces: Bool = true, returnAtEnd: Bool = false) -> String {
        prepareText(text, mode: mode, tabsToSpaces: tabsToSpaces, returnAtEnd: returnAtEnd)
    }

    private func analyze(_ text: String, mode: TypingMode = .keyCodes,
                         returnAtEnd: Bool = false) -> TextAnalysis {
        analyzeText(text, mode: mode, tabsToSpaces: true, returnAtEnd: returnAtEnd)
    }

    // MARK: prepareText

    func testLineEndingsBecomeSingleNewlines() {
        XCTAssertEqual(prepare("a\r\nb\rc\nd"), "a\nb\nc\nd")
    }

    func testTabsBecomeSpacesOnlyWhenAsked() {
        XCTAssertEqual(prepare("a\tb", tabsToSpaces: true), "a    b")
        XCTAssertEqual(prepare("a\tb", tabsToSpaces: false), "a\tb")
    }

    func testTypographicCharactersAreReplacedInKeyPressMode() {
        let fancy = "\u{201C}quoted\u{201D} \u{2018}single\u{2019} a\u{2013}b\u{2014}c\u{00A0}d\u{2026}"
        XCTAssertEqual(prepare(fancy, mode: .keyCodes), "\"quoted\" 'single' a-b-c d...")
    }

    func testTypographicCharactersAreKeptInUnicodeMode() {
        let fancy = "\u{201C}quoted\u{201D}"
        XCTAssertEqual(prepare(fancy, mode: .unicode), fancy)
    }

    func testReturnAtEndIsAddedOnce() {
        XCTAssertEqual(prepare("dir", returnAtEnd: true), "dir\n")
        XCTAssertEqual(prepare("dir\n", returnAtEnd: true), "dir\n")
        XCTAssertEqual(prepare("dir", returnAtEnd: false), "dir")
    }

    // MARK: analyzeText

    func testEmptyTextHasNothingToType() {
        XCTAssertEqual(analyze(""), TextAnalysis())
        XCTAssertEqual(analyze("", returnAtEnd: true), TextAnalysis())
    }

    func testCharacterAndLineCounts() {
        XCTAssertEqual(analyze("abc").characterCount, 3)
        XCTAssertEqual(analyze("abc").lineCount, 1)
        XCTAssertEqual(analyze("a\nb").lineCount, 2)
        XCTAssertEqual(analyze("a\nb\n").lineCount, 2)
        XCTAssertEqual(analyze("a\r\nb\r\n").characterCount, 4)
    }

    func testPlainScriptHasNoUntypeableCharacters() {
        let script = "Get-ChildItem -Path $Path | Where-Object { $_.Length -gt 1KB }\n"
        XCTAssertEqual(analyze(script).untypeableCount, 0)
    }

    func testUntypeableCharactersAreCountedInKeyPressMode() {
        let found = analyze("echo привет →")
        XCTAssertEqual(found.untypeableCount, 7)           // п р и в е т →
        XCTAssertEqual(found.untypeableDistinctCount, 7)
        XCTAssertEqual(found.untypeableSample, ["п", "р", "и"])
    }

    func testRepeatedUntypeableCharacterIsSampledOnce() {
        let found = analyze("яяя")
        XCTAssertEqual(found.untypeableCount, 3)
        XCTAssertEqual(found.untypeableDistinctCount, 1)
        XCTAssertEqual(found.untypeableSample, ["я"])
    }

    func testNothingIsUntypeableInUnicodeMode() {
        XCTAssertEqual(analyze("echo привет →", mode: .unicode).untypeableCount, 0)
    }

    // MARK: Warnings

    func testNoWarningsForShortPlainText() {
        let warnings = typingWarnings(analysis: analyze("ipconfig /all"), mode: .keyCodes,
                                      capsLockOn: false, delayMs: 5)
        XCTAssertEqual(warnings, [])
    }

    func testCapsLockWarningOnlyInKeyPressMode() {
        let found = analyze("abc")
        XCTAssertEqual(typingWarnings(analysis: found, mode: .keyCodes, capsLockOn: true, delayMs: 5),
                       ["Caps Lock is on"])
        XCTAssertEqual(typingWarnings(analysis: found, mode: .unicode, capsLockOn: true, delayMs: 5),
                       [])
    }

    func testSkippedCharactersWarning() {
        let one = typingWarnings(analysis: analyze("café"), mode: .keyCodes,
                                 capsLockOn: false, delayMs: 5)
        XCTAssertEqual(one, ["1 character will be skipped: é"])

        let many = typingWarnings(analysis: analyze("привет"), mode: .keyCodes,
                                  capsLockOn: false, delayMs: 5)
        XCTAssertEqual(many, ["6 characters will be skipped: п р и …"])
    }

    func testInvisibleCharacterIsShownAsCodePoint() {
        XCTAssertEqual(displayName(for: "\u{200B}"), "U+200B")
        XCTAssertEqual(displayName(for: "é"), "é")
    }

    func testLongTextWarning() {
        let long = String(repeating: "a", count: 10_000)
        let warnings = typingWarnings(analysis: analyze(long), mode: .keyCodes,
                                      capsLockOn: false, delayMs: 5)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].hasPrefix("Long text: about "), warnings[0])
    }

    // MARK: Estimates

    func testEstimateGrowsWithDelay() {
        let fast = estimatedSeconds(characters: 1000, lines: 10, delayMs: 1)
        let slow = estimatedSeconds(characters: 1000, lines: 10, delayMs: 20)
        XCTAssertLessThan(fast, slow)
    }

    func testDurationLabels() {
        XCTAssertEqual(durationLabel(0.2), "about 1 s")
        XCTAssertEqual(durationLabel(6.1), "about 7 s")
        XCTAssertEqual(durationLabel(59.9), "about 60 s")
        XCTAssertEqual(durationLabel(60), "about 1 min")
        XCTAssertEqual(durationLabel(170), "about 3 min")
    }
}
