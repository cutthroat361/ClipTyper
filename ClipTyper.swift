// ClipTyper — menu-bar app that types the clipboard as keystrokes.
// Built for remote sessions (Windows App / RDP, ScreenConnect, Datto RMM) where paste is
// blocked or truncated. Press the global shortcut and the clipboard is typed into whatever
// window has focus. Press the shortcut again, or click the menu-bar icon, to stop.
//
// Click the menu-bar icon for the quick panel: enable/disable, rebind the shortcut, speed, mode.
//
// Build: ./build.sh   (needs Xcode Command Line Tools). See README.md.

import Cocoa
import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Shortcut model

struct Shortcut {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon modifier mask (cmdKey, optionKey, controlKey, shiftKey)
}

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

// MARK: - US ANSI key table (physical key -> characters)

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

let usKeyMap: [Character: (code: CGKeyCode, shift: Bool)] = {
    var map: [Character: (code: CGKeyCode, shift: Bool)] = [:]
    map[" "] = (CGKeyCode(kVK_Space), false)
    for key in usKeyTable {
        map[key.plain] = (CGKeyCode(key.code), false)
        map[key.shifted] = (CGKeyCode(key.code), true)
    }
    return map
}()

// Characters that often sneak into scripts copied from web pages, mail or Word.
// They have no key on a US keyboard, so in key-press mode they are swapped for the plain form.
let typographicReplacements: [(String, String)] = [
    ("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201C}", "\""), ("\u{201D}", "\""),
    ("\u{2013}", "-"), ("\u{2014}", "-"), ("\u{00A0}", " "), ("\u{2026}", "..."),
]

func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var mask: UInt32 = 0
    if flags.contains(.command) { mask |= UInt32(cmdKey) }
    if flags.contains(.option) { mask |= UInt32(optionKey) }
    if flags.contains(.control) { mask |= UInt32(controlKey) }
    if flags.contains(.shift) { mask |= UInt32(shiftKey) }
    return mask
}

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

enum TypingMode: String {
    case keyCodes   // physical US-layout key presses: works through RDP / ScreenConnect / Datto
    case unicode    // characters sent directly: any language, for Mac apps and VNC
}

// MARK: - Global hot key (Carbon; needs no extra permission)

final class HotKeyCenter {
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData = userData else { return noErr }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            center.onPress?()
            return noErr
        }, 1, &spec, pointer, &handlerRef)
    }

    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x434C_5459), id: 1)   // 'CLTY'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}

// MARK: - Typing engine

final class Typer {
    struct Options {
        var mode: TypingMode
        var delayMs: Int
        var startDelay: Double
        var tabsToSpaces: Bool
        var returnAtEnd: Bool
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

    func cancel() {
        lock.lock()
        cancelRequested = true
        lock.unlock()
    }

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
        var prepared = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if options.tabsToSpaces {
            prepared = prepared.replacingOccurrences(of: "\t", with: "    ")
        }
        if options.mode == .keyCodes {
            for (from, to) in typographicReplacements {
                prepared = prepared.replacingOccurrences(of: from, with: to)
            }
        }
        if options.returnAtEnd && !prepared.hasSuffix("\n") {
            prepared += "\n"
        }

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
        let holdMicros = useconds_t(max(500, delay * 500))
        let gapMicros = useconds_t(delay * 1000)
        let lineMicros = useconds_t(max(30_000, delay * 4000))
        var shiftIsDown = false

        // Flags exactly as a real keyboard reports them. 0x2 is the "left Shift" device bit:
        // RDP clients that forward scancodes read it to decide whether Shift is held, and
        // ignore the generic Shift flag on its own (everything arrived lower-case without it).
        let shiftFlags = CGEventFlags(rawValue:
            CGEventFlags.maskShift.rawValue | CGEventFlags.maskNonCoalesced.rawValue | 0x2)
        let plainFlags = CGEventFlags.maskNonCoalesced
        let shiftSettleMicros = max(holdMicros, 4000)

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

// MARK: - App state (settings + actions), shared by the hot key and the panel

final class AppModel: ObservableObject {
    private let defaults = UserDefaults.standard
    private let hotKeys = HotKeyCenter()
    private let typer = Typer()
    private var recordMonitor: Any?
    private var lastPasteboardChange = -1

    /// Called when the menu-bar icon should be redrawn.
    var onAppearanceChange: (() -> Void)?
    /// Closes the panel if it is open and hands focus back. Returns true if it was open.
    var closePanel: (() -> Bool)?

    // Settings (saved automatically)
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "enabled")
            applyHotKey()
            onAppearanceChange?()
        }
    }
    @Published var shortcut: Shortcut {
        didSet {
            defaults.set(Int(shortcut.keyCode), forKey: "hotKeyCode")
            defaults.set(Int(shortcut.modifiers), forKey: "hotKeyModifiers")
            applyHotKey()
        }
    }
    @Published var mode: TypingMode {
        didSet { defaults.set(mode.rawValue, forKey: "mode") }
    }
    @Published var delayMs: Double {
        didSet { defaults.set(Int(delayMs), forKey: "delayMs") }
    }
    @Published var startDelaySeconds: Int {
        didSet { defaults.set(startDelaySeconds, forKey: "startDelaySeconds") }
    }
    @Published var tabsToSpaces: Bool {
        didSet { defaults.set(tabsToSpaces, forKey: "tabsToSpaces") }
    }
    @Published var returnAtEnd: Bool {
        didSet { defaults.set(returnAtEnd, forKey: "returnAtEnd") }
    }
    @Published var launchAtLogin: Bool

    // Live state
    @Published var isTyping = false
    @Published var progress = 0.0
    @Published var statusText = "Ready"
    @Published var isRecording = false
    @Published var recordHint = ""
    @Published var hotKeyRegistered = true
    @Published var accessibilityGranted = false
    @Published var clipboardCharacters = 0
    @Published var clipboardLines = 0

    init() {
        let stored = UserDefaults.standard
        stored.register(defaults: [
            "enabled": true,
            "hotKeyCode": kVK_ANSI_V,
            "hotKeyModifiers": controlKey | optionKey,
            "mode": TypingMode.keyCodes.rawValue,
            "delayMs": 5,
            "startDelaySeconds": 0,
            "tabsToSpaces": true,
            "returnAtEnd": false,
        ])
        enabled = stored.bool(forKey: "enabled")
        shortcut = Shortcut(keyCode: UInt32(stored.integer(forKey: "hotKeyCode")),
                            modifiers: UInt32(stored.integer(forKey: "hotKeyModifiers")))
        mode = TypingMode(rawValue: stored.string(forKey: "mode") ?? "") ?? .keyCodes
        delayMs = Double(max(1, stored.integer(forKey: "delayMs")))
        startDelaySeconds = stored.integer(forKey: "startDelaySeconds")
        tabsToSpaces = stored.bool(forKey: "tabsToSpaces")
        returnAtEnd = stored.bool(forKey: "returnAtEnd")
        launchAtLogin = SMAppService.mainApp.status == .enabled

        hotKeys.onPress = { [weak self] in
            self?.toggleTyping(fromHotKey: true)
        }
        applyHotKey()
        refresh()
    }

    // MARK: Hot key

    private func applyHotKey() {
        if enabled && !isRecording {
            hotKeyRegistered = hotKeys.register(shortcut)
        } else {
            hotKeys.unregister()
        }
    }

    // MARK: Typing

    func typeFromPanel() {
        toggleTyping(fromHotKey: false)
    }

    func stopTyping() {
        typer.cancel()
    }

    private func toggleTyping(fromHotKey: Bool) {
        if typer.isRunning {
            typer.cancel()
            return
        }
        guard AXIsProcessTrusted() else {
            accessibilityGranted = false
            statusText = "Needs Accessibility permission"
            promptForAccessibility()
            return
        }
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            statusText = "Clipboard has no text"
            NSSound.beep()
            return
        }

        // If the panel is open it has keyboard focus; close it and give focus back first,
        // then leave a moment for the previous window to become active again.
        let panelWasOpen = closePanel?() ?? false
        var startDelay = Double(startDelaySeconds)
        if panelWasOpen {
            startDelay = max(startDelay, 0.7)
        }

        let options = Typer.Options(
            mode: mode,
            delayMs: Int(delayMs),
            startDelay: startDelay,
            tabsToSpaces: tabsToSpaces,
            returnAtEnd: returnAtEnd,
            triggerKey: fromHotKey ? CGKeyCode(shortcut.keyCode) : nil
        )

        isTyping = true
        progress = 0
        statusText = "Typing…"
        onAppearanceChange?()

        typer.start(text: text, options: options, progress: { [weak self] done, total in
            guard let self = self else { return }
            self.progress = Double(done) / Double(max(total, 1))
            self.onAppearanceChange?()
        }, completion: { [weak self] result in
            self?.finished(result)
        })
    }

    private func finished(_ result: Typer.Result) {
        var text: String
        if result.cancelled {
            text = "Stopped after \(result.typed) of \(result.total) characters"
        } else {
            text = "Typed \(result.typed) characters"
        }
        if result.skipped > 0 {
            text += ", skipped \(result.skipped) not on a US keyboard"
            NSSound.beep()
        }
        statusText = text
        isTyping = false
        progress = 0
        onAppearanceChange?()
    }

    // MARK: Shortcut recording (inside the panel)

    func startRecording() {
        if isRecording { return }
        isRecording = true
        recordHint = "F-keys work on their own. Other keys need ⌃, ⌥ or ⌘. Esc cancels."
        hotKeys.unregister()
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecording(event)
            return nil
        }
    }

    func stopRecording() {
        if !isRecording { return }
        if let monitor = recordMonitor {
            NSEvent.removeMonitor(monitor)
            recordMonitor = nil
        }
        isRecording = false
        applyHotKey()
    }

    private func handleRecording(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = Int(event.keyCode)

        if code == kVK_Escape && flags.isEmpty {
            stopRecording()
            return
        }

        let isFunctionKey = functionKeyNames[code] != nil
        let hasMainModifier = !flags.intersection([.command, .option, .control]).isEmpty
        if !isFunctionKey && !hasMainModifier {
            NSSound.beep()
            recordHint = "That key needs ⌃, ⌥ or ⌘ held with it. Esc cancels."
            return
        }

        shortcut = Shortcut(keyCode: UInt32(code), modifiers: carbonModifiers(from: flags))
        stopRecording()
    }

    // MARK: Panel data

    /// Refreshes permission state and clipboard size. Called while the panel is open.
    func refresh() {
        let granted = AXIsProcessTrusted()
        if granted != accessibilityGranted {
            accessibilityGranted = granted
        }

        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != lastPasteboardChange {
            lastPasteboardChange = pasteboard.changeCount
            let text = (pasteboard.string(forType: .string) ?? "")
                .replacingOccurrences(of: "\r\n", with: "\n")
            clipboardCharacters = text.count
            clipboardLines = text.isEmpty ? 0 : text.components(separatedBy: "\n").count
        }
    }

    var clipboardSummary: String {
        if clipboardCharacters == 0 {
            return "No text on the clipboard"
        }
        let seconds = Int((Double(clipboardCharacters) * (delayMs * 1.5 + 1) / 1000).rounded(.up))
        let lineWord = clipboardLines == 1 ? "line" : "lines"
        return "\(clipboardCharacters) characters · \(clipboardLines) \(lineWord) · about \(seconds) s"
    }

    // MARK: System

    func promptForAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        let address = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: address) {
            NSWorkspace.shared.open(url)
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            statusText = "Launch at login failed: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Panel UI

let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
    }
}

struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.14)))
    }
}

struct PanelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !model.accessibilityGranted {
                permissionCard
            }
            clipboardCard
            shortcutCard
            typingCard
            optionsCard
            footer
        }
        .padding(14)
        .frame(width: 350)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 26, height: 26)
            Text("ClipTyper")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Text(model.enabled ? "Shortcut on" : "Shortcut off")
                .font(.caption)
                .foregroundColor(.secondary)
            Toggle("", isOn: $model.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var permissionCard: some View {
        Card {
            Label("Accessibility permission needed", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundColor(.orange)
            Text("ClipTyper cannot press keys until you allow it in System Settings.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Accessibility Settings") {
                model.openAccessibilitySettings()
            }
        }
    }

    private var clipboardCard: some View {
        Card {
            Text("Clipboard")
                .font(.headline)
            Text(model.clipboardSummary)
                .font(.caption)
                .foregroundColor(.secondary)
            Button(action: { model.typeFromPanel() }) {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                    Text("Type Clipboard")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.clipboardCharacters == 0 || !model.accessibilityGranted)
            Text(model.statusText)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shortcutCard: some View {
        Card {
            HStack(spacing: 8) {
                Text("Shortcut")
                    .font(.headline)
                Spacer()
                if model.isRecording {
                    Text("Press keys…")
                        .foregroundColor(.accentColor)
                    Button("Cancel") {
                        model.stopRecording()
                    }
                } else {
                    KeyCap(text: shortcutLabel(model.shortcut))
                    Button("Change") {
                        model.startRecording()
                    }
                }
            }
            if model.isRecording {
                Text(model.recordHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.enabled && !model.hotKeyRegistered {
                Text("This shortcut could not be registered. Pick another one.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var typingCard: some View {
        Card {
            Text("Typing")
                .font(.headline)
            Picker("", selection: $model.mode) {
                Text("Key presses").tag(TypingMode.keyCodes)
                Text("Unicode").tag(TypingMode.unicode)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(model.mode == .keyCodes
                 ? "US-layout key presses. Use for RDP, ScreenConnect and Datto."
                 : "Sends characters directly, in any language. For Mac apps and VNC.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Per-character delay")
                Spacer()
                Text("\(Int(model.delayMs)) ms")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(value: Binding(get: { model.delayMs },
                                  set: { model.delayMs = $0.rounded() }),
                   in: 1...50)

            Stepper(value: $model.startDelaySeconds, in: 0...10) {
                HStack {
                    Text("Wait before typing")
                    Spacer()
                    Text(model.startDelaySeconds == 0 ? "None" : "\(model.startDelaySeconds) s")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var optionsCard: some View {
        Card {
            Toggle("Convert tabs to 4 spaces", isOn: $model.tabsToSpaces)
            Toggle("Press Return at the end", isOn: $model.returnAtEnd)
            Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin },
                                                    set: { model.setLaunchAtLogin($0) }))
        }
    }

    private var footer: some View {
        HStack {
            Text("ClipTyper \(appVersion) · While typing, click the menu-bar icon to stop.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }
}

// MARK: - App delegate (menu-bar icon + panel)

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let model = AppModel()
    private let popover = NSPopover()
    private var previousApp: NSRunningApplication?
    private var refreshTimer: Timer?
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusItemClicked(_:))
        }

        let hosting = NSHostingController(rootView: PanelView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self

        model.onAppearanceChange = { [weak self] in
            self?.updateIcon()
        }
        model.closePanel = { [weak self] in
            guard let self = self, self.popover.isShown else { return false }
            self.closePopover(returnFocus: true)
            return true
        }
        updateIcon()

        if !AXIsProcessTrusted() {
            model.promptForAccessibility()
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        // The panel takes keyboard focus, so never open it mid-typing: a click stops instead.
        if model.isTyping {
            model.stopTyping()
            return
        }
        if popover.isShown {
            closePopover(returnFocus: true)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }

        // Remember which app had focus so it can get focus back when the panel closes.
        let front = NSWorkspace.shared.frontmostApplication
        if let front = front, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }

        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        let model = self.model
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            model.refresh()
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    private func closePopover(returnFocus: Bool) {
        popover.close()
        if returnFocus, let app = previousApp, !app.isTerminated {
            app.activate(options: [])
        }
    }

    func popoverDidClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        model.stopRecording()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let name = model.isTyping ? "keyboard.fill" : "keyboard"
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: "ClipTyper") {
            button.image = image
            button.title = model.isTyping ? " \(Int(model.progress * 100))%" : ""
        } else {
            button.image = nil
            button.title = model.isTyping ? "⌨︎ \(Int(model.progress * 100))%" : "⌨︎"
        }
        // Dimmed icon = shortcut switched off.
        button.appearsDisabled = !model.enabled
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
