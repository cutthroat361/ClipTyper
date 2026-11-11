import Foundation

/// How characters are sent to the focused window.
enum TypingMode: String {
    /// Physical US-layout key presses. Works through RDP, ScreenConnect and Datto.
    case keyCodes
    /// Characters sent directly, in any language. For Mac apps and VNC.
    case unicode
}

// MARK: - Preparing the text

/// Cleans up clipboard text so it types predictably. Used both by the typer and by the
/// pre-typing checks, so what is counted is exactly what gets typed.
func prepareText(_ text: String, mode: TypingMode, tabsToSpaces: Bool, returnAtEnd: Bool) -> String {
    // Windows (CRLF) and old Mac (CR) line endings both become a single Return press.
    var prepared = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    if tabsToSpaces {
        // Tab triggers autocomplete in PowerShell and moves focus in forms.
        prepared = prepared.replacingOccurrences(of: "\t", with: "    ")
    }
    if mode == .keyCodes {
        for (from, to) in typographicReplacements {
            prepared = prepared.replacingOccurrences(of: from, with: to)
        }
    }
    if returnAtEnd && !prepared.hasSuffix("\n") {
        prepared += "\n"
    }
    return prepared
}

/// Whether a character of prepared text can be typed in the given mode.
func canType(_ character: Character, mode: TypingMode) -> Bool {
    if character == "\n" || character == "\t" { return true }
    if mode == .unicode { return true }
    return usKeyMap[character] != nil
}

// MARK: - Checking the text before typing

/// What the clipboard text looks like once prepared: its size and anything that cannot be typed.
struct TextAnalysis: Equatable {
    var characterCount = 0
    var lineCount = 0
    /// How many characters will be skipped.
    var untypeableCount = 0
    /// How many different characters that is.
    var untypeableDistinctCount = 0
    /// The first few of them, to show as an example.
    var untypeableSample: [Character] = []
}

func analyzeText(_ text: String, mode: TypingMode, tabsToSpaces: Bool, returnAtEnd: Bool) -> TextAnalysis {
    var analysis = TextAnalysis()
    if text.isEmpty { return analysis }

    let prepared = prepareText(text, mode: mode, tabsToSpaces: tabsToSpaces, returnAtEnd: returnAtEnd)
    var newlines = 0
    var distinct = Set<Character>()
    for character in prepared {
        analysis.characterCount += 1
        if character == "\n" { newlines += 1 }
        if !canType(character, mode: mode) {
            analysis.untypeableCount += 1
            if distinct.insert(character).inserted && analysis.untypeableSample.count < 3 {
                analysis.untypeableSample.append(character)
            }
        }
    }
    analysis.untypeableDistinctCount = distinct.count
    analysis.lineCount = newlines + (prepared.hasSuffix("\n") ? 0 : 1)
    return analysis
}

/// Rough typing time. Each character costs the delay plus the time the key is held down;
/// each line adds the pause after Return.
func estimatedSeconds(characters: Int, lines: Int, delayMs: Int) -> Double {
    let perCharacter = Double(delayMs) * 1.5 + 1
    let perLine = Double(max(30, delayMs * 4))
    return (Double(characters) * perCharacter + Double(lines) * perLine) / 1000
}

/// "about 7 s" or "about 3 min".
func durationLabel(_ seconds: Double) -> String {
    if seconds < 60 {
        return "about \(max(1, Int(seconds.rounded(.up)))) s"
    }
    return "about \(Int((seconds / 60).rounded())) min"
}

/// Typing that would take at least this long counts as "long" and gets a warning.
let longTextSeconds = 60.0

/// Things worth telling the user before typing starts. An empty list means nothing to report.
func typingWarnings(analysis: TextAnalysis, mode: TypingMode, capsLockOn: Bool, delayMs: Int) -> [String] {
    var warnings: [String] = []

    if capsLockOn && mode == .keyCodes {
        warnings.append("Caps Lock is on")
    }

    if analysis.untypeableCount > 0 {
        let noun = analysis.untypeableCount == 1 ? "character" : "characters"
        let sample = analysis.untypeableSample.map { displayName(for: $0) }.joined(separator: " ")
        let more = analysis.untypeableDistinctCount > analysis.untypeableSample.count ? " …" : ""
        warnings.append("\(analysis.untypeableCount) \(noun) will be skipped: \(sample)\(more)")
    }

    let seconds = estimatedSeconds(characters: analysis.characterCount,
                                   lines: analysis.lineCount, delayMs: delayMs)
    if seconds >= longTextSeconds {
        warnings.append("Long text: \(durationLabel(seconds))")
    }

    return warnings
}

/// The character itself, or its code point when it is invisible (zero-width space and similar).
func displayName(for character: Character) -> String {
    guard let scalar = character.unicodeScalars.first else { return "" }
    switch scalar.properties.generalCategory {
    case .control, .format, .spaceSeparator, .lineSeparator, .paragraphSeparator,
         .unassigned, .privateUse, .surrogate:
        return String(format: "U+%04X", scalar.value)
    default:
        return String(character)
    }
}
