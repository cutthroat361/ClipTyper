import Cocoa
import Carbon.HIToolbox

/// Types text into whatever window has focus by posting keyboard events.
/// Runs on a background thread so the menu bar stays responsive and typing can be stopped.
final class Typer {
    struct Options {
        var mode: TypingMode
        /// Pause after each character, in milliseconds.
        var delayMs: Int
        /// Seconds to wait before the first key, so there is time to click into the target.
        var startDelay: Double
        var tabsToSpaces: Bool
        var returnAtEnd: Bool
        /// The shortcut key that started this run, if any. Typing waits until it is released.
        var triggerKey: CGKeyCode?
    }

    struct Result {
        var typed: Int
        var skipped: Int
        var total: Int
        var cancelled: Bool
    }

    private let lock = NSLock()
    private var running = false
    private var cancelRequested = false

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelRequested
    }

    /// Asks the current run to stop. It stops before the next character.
    func cancel() {
        lock.lock()
        cancelRequested = true
        lock.unlock()
    }

    /// Starts typing. Does nothing if a run is already in progress.
    /// `progress` and `completion` are always called on the main thread.
    func start(text: String, options: Options,
               progress: @escaping (Int, Int) -> Void,
               completion: @escaping (Result) -> Void) {
        lock.lock()
        if running {
            lock.unlock()
            return
        }
        running = true
        cancelRequested = false
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.run(text: text, options: options, progress: progress)
            self.lock.lock()
            self.running = false
            self.lock.unlock()
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func run(text: String, options: Options,
                     progress: @escaping (Int, Int) -> Void) -> Result {
        let prepared = prepareText(text, mode: options.mode,
                                   tabsToSpaces: options.tabsToSpaces,
                                   returnAtEnd: options.returnAtEnd)
        let characters = Array(prepared)
        let total = characters.count
        var typed = 0
        var skipped = 0

        // Optional delay so there is time to click into the target window.
        var waited = 0.0
        while waited < options.startDelay {
            if isCancelled { return Result(typed: 0, skipped: 0, total: total, cancelled: true) }
            usleep(50_000)
            waited += 0.05
        }

        // The shortcut keys are still physically down right after the trigger. Typing now would
        // turn every character into Ctrl+char / Fn+char in the remote session, so wait for release.
        waitForRelease(of: options.triggerKey)

        let source = CGEventSource(stateID: .hidSystemState)
        let delay = max(options.delayMs, 0)
        let holdMicros = useconds_t(max(500, delay * 500))        // how long a key stays down
        let gapMicros = useconds_t(delay * 1000)                  // pause between characters
        let lineMicros = useconds_t(max(30_000, delay * 4000))    // extra pause after Return
        var shiftIsDown = false

        // Flags exactly as a real keyboard reports them. 0x2 is the "left Shift" device bit:
        // RDP clients that forward scancodes read it to decide whether Shift is held, and
        // ignore the generic Shift flag on its own (everything arrived lower-case without it).
        let shiftFlags = CGEventFlags(rawValue:
            CGEventFlags.maskShift.rawValue | CGEventFlags.maskNonCoalesced.rawValue | 0x2)
        let plainFlags = CGEventFlags.maskNonCoalesced
        let shiftSettleMicros = max(holdMicros, 4000)

        // Shift is pressed and released as its own key, like a person does, and only when the
        // next character needs a different Shift state from the previous one.
        func setShift(_ down: Bool) {
            if down == shiftIsDown { return }
            if let event = CGEvent(keyboardEventSource: source,
                                   virtualKey: CGKeyCode(kVK_Shift), keyDown: down) {
                event.type = .flagsChanged
                event.flags = down ? shiftFlags : plainFlags
                event.post(tap: .cghidEventTap)
            }
            shiftIsDown = down
            usleep(shiftSettleMicros)
        }

        func tapKey(_ code: CGKeyCode, shift: Bool) {
            setShift(shift)
            let flags = shift ? shiftFlags : plainFlags
            if let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) {
                down.flags = flags
                down.post(tap: .cghidEventTap)
            }
            usleep(holdMicros)
            if let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) {
                up.flags = flags
                up.post(tap: .cghidEventTap)
            }
        }

        // Unicode mode: the event carries the character itself instead of a key position.
        func typeUnicode(_ character: Character) {
            setShift(false)
            let units = Array(String(character).utf16)
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.flags = plainFlags
                down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                down.post(tap: .cghidEventTap)
            }
            usleep(holdMicros)
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.flags = plainFlags
                up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                up.post(tap: .cghidEventTap)
            }
        }

        var cancelled = false
        for (index, character) in characters.enumerated() {
            if isCancelled {
                cancelled = true
                break
            }

            if character == "\n" {
                tapKey(CGKeyCode(kVK_Return), shift: false)
                typed += 1
                usleep(lineMicros)   // give the remote shell a moment to take the line
            } else if character == "\t" {
                tapKey(CGKeyCode(kVK_Tab), shift: false)
                typed += 1
            } else if options.mode == .unicode {
                typeUnicode(character)
                typed += 1
            } else if let key = usKeyMap[character] {
                tapKey(key.code, shift: key.shift)
                typed += 1
            } else {
                // No key for this character on a US keyboard.
                skipped += 1
                continue
            }

            usleep(gapMicros)

            if index % 20 == 0 {
                let done = index + 1
                DispatchQueue.main.async { progress(done, total) }
            }
        }

        setShift(false)
        return Result(typed: typed, skipped: skipped, total: total, cancelled: cancelled)
    }

    /// Waits (up to three seconds) until the shortcut key and all modifiers are released.
    private func waitForRelease(of triggerKey: CGKeyCode?) {
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate,
                                       .maskShift, .maskSecondaryFn]
        var waited = 0
        while waited < 3_000_000 {
            let flags = CGEventSource.flagsState(.hidSystemState)
            let modifierHeld = !flags.intersection(modifiers).isEmpty
            var keyHeld = false
            if let key = triggerKey {
                keyHeld = CGEventSource.keyState(.hidSystemState, key: key)
            }
            if !modifierHeld && !keyHeld { break }
            usleep(20_000)
            waited += 20_000
        }
        usleep(60_000)
    }
}
