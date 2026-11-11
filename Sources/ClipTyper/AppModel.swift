import Cocoa
import Carbon.HIToolbox
import ServiceManagement

/// The app's state and behaviour: saved settings, the global shortcut, and the whole
/// "type the clipboard" flow. The panel reads and changes it; the app delegate listens to it
/// to update the menu-bar icon and the on-screen HUD.
final class AppModel: ObservableObject {
    /// What the app is doing right now.
    private enum Phase {
        case idle
        /// A warning is on screen, waiting for a second press of the shortcut (or Esc).
        case confirming
        case typing
    }

    private enum HotKeyID {
        static let main: UInt32 = 1
        static let escape: UInt32 = 2
    }

    private let defaults = UserDefaults.standard
    private let hotKeys = HotKeyCenter()
    private let typer = Typer()
    private var phase = Phase.idle
    private var recordMonitor: Any?

    // Clipboard analysis shown in the panel, recalculated only when its inputs change.
    private var analysisKey = ""
    private var analysis = TextAnalysis()

    // Text held while a warning waits for confirmation, and the clipboard version it came from.
    private var pendingText: String?
    private var pendingChangeCount = 0
    private var confirmTimeout: DispatchWorkItem?
    /// Clipboard version being typed, so "clear after typing" never wipes something newer.
    private var typingChangeCount = 0
    private var hudHide: DispatchWorkItem?

    /// Called when the menu-bar icon should be redrawn.
    var onAppearanceChange: (() -> Void)?
    /// Closes the panel if it is open and hands focus back. Returns true if it was open.
    var closePanel: (() -> Bool)?
    /// Called when the on-screen HUD should change; nil means hide it.
    var onHUDChange: ((HUDContent?) -> Void)?

    private var hud: HUDContent? {
        didSet { onHUDChange?(hud) }
    }

    // MARK: Settings (saved automatically)

    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "enabled")
            if !enabled { cancelConfirmation() }
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
        didSet {
            defaults.set(mode.rawValue, forKey: "mode")
            refresh()
        }
    }
    @Published var delayMs: Double {
        didSet {
            defaults.set(Int(delayMs), forKey: "delayMs")
            refresh()
        }
    }
    @Published var startDelaySeconds: Int {
        didSet { defaults.set(startDelaySeconds, forKey: "startDelaySeconds") }
    }
    @Published var tabsToSpaces: Bool {
        didSet {
            defaults.set(tabsToSpaces, forKey: "tabsToSpaces")
            refresh()
        }
    }
    @Published var returnAtEnd: Bool {
        didSet {
            defaults.set(returnAtEnd, forKey: "returnAtEnd")
            refresh()
        }
    }
    @Published var clearClipboardAfter: Bool {
        didSet { defaults.set(clearClipboardAfter, forKey: "clearClipboardAfter") }
    }
    @Published var launchAtLogin: Bool

    // MARK: Live state

    @Published var isTyping = false
    @Published var progress = 0.0
    /// The line under the Type Clipboard button: the outcome of the last attempt.
    @Published var statusText = "Ready" {
        didSet { statusChangeCount = NSPasteboard.general.changeCount }
    }
    /// Clipboard version that `statusText` was written for. See `refresh()`.
    private var statusChangeCount = -1
    @Published var isRecording = false
    @Published var recordHint = ""
    @Published var hotKeyRegistered = true
    @Published var accessibilityGranted = false
    @Published var clipboardCharacters = 0
    @Published var clipboardLines = 0
    @Published var clipboardWarnings: [String] = []

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
            "clearClipboardAfter": false,
        ])
        enabled = stored.bool(forKey: "enabled")
        shortcut = Shortcut(keyCode: UInt32(stored.integer(forKey: "hotKeyCode")),
                            modifiers: UInt32(stored.integer(forKey: "hotKeyModifiers")))
        mode = TypingMode(rawValue: stored.string(forKey: "mode") ?? "") ?? .keyCodes
        delayMs = Double(max(1, stored.integer(forKey: "delayMs")))
        startDelaySeconds = stored.integer(forKey: "startDelaySeconds")
        tabsToSpaces = stored.bool(forKey: "tabsToSpaces")
        returnAtEnd = stored.bool(forKey: "returnAtEnd")
        clearClipboardAfter = stored.bool(forKey: "clearClipboardAfter")
        launchAtLogin = SMAppService.mainApp.status == .enabled

        applyHotKey()
        refresh()
    }

    // MARK: Hot keys

    private func applyHotKey() {
        if enabled && !isRecording {
            hotKeyRegistered = hotKeys.register(id: HotKeyID.main, shortcut: shortcut) { [weak self] in
                self?.shortcutPressed()
            }
        } else {
            hotKeys.unregister(id: HotKeyID.main)
        }
    }

    /// Esc is only a global shortcut while there is something to stop or cancel. The rest of
    /// the time it reaches other apps as usual.
    private func setEscapeHotKey(_ on: Bool) {
        if on {
            let escape = Shortcut(keyCode: UInt32(kVK_Escape), modifiers: 0)
            hotKeys.register(id: HotKeyID.escape, shortcut: escape) { [weak self] in
                self?.escapePressed()
            }
        } else {
            hotKeys.unregister(id: HotKeyID.escape)
        }
    }

    private func shortcutPressed() {
        switch phase {
        case .typing:
            typer.cancel()
        case .confirming:
            // Second press: the warning was seen, go ahead.
            let text = pendingText
            let changeCount = pendingChangeCount
            endConfirmation()
            if let text = text {
                startTyping(text: text, changeCount: changeCount, fromHotKey: true)
            }
        case .idle:
            begin(fromHotKey: true)
        }
    }

    private func escapePressed() {
        switch phase {
        case .typing:
            typer.cancel()
        case .confirming:
            cancelConfirmation()
        case .idle:
            break
        }
    }

    // MARK: Typing

    /// "Type Clipboard" in the panel. The panel already shows any warnings, so no second step.
    func typeFromPanel() {
        switch phase {
        case .typing:
            typer.cancel()
        case .confirming:
            cancelConfirmation()
            begin(fromHotKey: false)
        case .idle:
            begin(fromHotKey: false)
        }
    }

    func stopTyping() {
        typer.cancel()
    }

    private func begin(fromHotKey: Bool) {
        guard AXIsProcessTrusted() else {
            accessibilityGranted = false
            statusText = "Needs Accessibility permission"
            promptForAccessibility()
            return
        }
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            statusText = "Clipboard has no text"
            if fromHotKey {
                flashHUD(.message("Clipboard has no text"), seconds: 1.6)
            }
            NSSound.beep()
            return
        }

        if fromHotKey {
            let found = analyzeText(text, mode: mode, tabsToSpaces: tabsToSpaces, returnAtEnd: returnAtEnd)
            let warnings = typingWarnings(analysis: found, mode: mode,
                                          capsLockOn: capsLockIsOn(), delayMs: Int(delayMs))
            if !warnings.isEmpty {
                askToConfirm(text: text, changeCount: changeCount, warnings: warnings)
                return
            }
        }
        startTyping(text: text, changeCount: changeCount, fromHotKey: fromHotKey)
    }

    private func startTyping(text: String, changeCount: Int, fromHotKey: Bool) {
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

        phase = .typing
        typingChangeCount = changeCount
        setEscapeHotKey(true)
        isTyping = true
        progress = 0
        statusText = "Typing…"
        cancelHUDHide()
        hud = .progress(0)
        onAppearanceChange?()

        typer.start(text: text, options: options, progress: { [weak self] done, total in
            guard let self = self, self.phase == .typing else { return }
            self.progress = Double(done) / Double(max(total, 1))
            self.hud = .progress(self.progress)
            self.onAppearanceChange?()
        }, completion: { [weak self] result in
            self?.finished(result)
        })
    }

    private func finished(_ result: Typer.Result) {
        phase = .idle
        setEscapeHotKey(false)

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
        // Only after a complete run, and only if the clipboard still holds what was typed.
        if clearClipboardAfter && !result.cancelled
            && NSPasteboard.general.changeCount == typingChangeCount {
            NSPasteboard.general.clearContents()
            text += ", clipboard cleared"
        }
        statusText = text
        isTyping = false
        progress = 0
        onAppearanceChange?()

        if result.cancelled {
            flashHUD(.message("Stopped"), seconds: 0.9)
        } else if result.skipped > 0 {
            flashHUD(.message("Done · \(result.skipped) skipped"), seconds: 2.5)
        } else {
            flashHUD(.message("Done"), seconds: 0.9)
        }
        refresh()
    }

    // MARK: Warnings before typing

    /// Shows the warnings on screen and waits for a second press of the shortcut.
    /// Nothing is typed unless that press comes; Esc or a few seconds of waiting cancels.
    private func askToConfirm(text: String, changeCount: Int, warnings: [String]) {
        phase = .confirming
        pendingText = text
        pendingChangeCount = changeCount
        setEscapeHotKey(true)
        statusText = "Waiting: " + warnings.joined(separator: "; ")
        cancelHUDHide()
        hud = .warning(lines: warnings,
                       hint: "\(shortcutLabel(shortcut)) again to type anyway · esc to cancel")

        let timeout = DispatchWorkItem { [weak self] in
            self?.cancelConfirmation()
        }
        confirmTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
    }

    /// Drops a pending warning without typing. Does nothing if none is showing.
    func cancelConfirmation() {
        guard phase == .confirming else { return }
        endConfirmation()
        statusText = "Cancelled"
        hud = nil
    }

    private func endConfirmation() {
        confirmTimeout?.cancel()
        confirmTimeout = nil
        pendingText = nil
        phase = .idle
        setEscapeHotKey(false)
    }

    private func capsLockIsOn() -> Bool {
        CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
    }

    // MARK: HUD

    /// Shows a note on screen for a moment, then hides the HUD.
    private func flashHUD(_ content: HUDContent, seconds: Double) {
        cancelHUDHide()
        hud = content
        let work = DispatchWorkItem { [weak self] in
            self?.hud = nil
        }
        hudHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelHUDHide() {
        hudHide?.cancel()
        hudHide = nil
    }

    // MARK: Shortcut recording (inside the panel)

    func startRecording() {
        if isRecording { return }
        isRecording = true
        recordHint = "F-keys work on their own. Other keys need ⌃, ⌥ or ⌘. Esc cancels."
        hotKeys.unregister(id: HotKeyID.main)
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

    /// Refreshes permission state, clipboard size and warnings. Called while the panel is open
    /// and whenever a setting that affects them changes.
    func refresh() {
        let granted = AXIsProcessTrusted()
        if granted != accessibilityGranted {
            accessibilityGranted = granted
        }

        // Reading and scanning the clipboard is only repeated when it, or a setting that
        // changes the result, is different from last time.
        let pasteboard = NSPasteboard.general

        // The status line describes the last attempt ("Clipboard has no text", "Typed 40
        // characters"). Once something new has been copied it no longer applies.
        if phase == .idle && pasteboard.changeCount != statusChangeCount {
            statusChangeCount = pasteboard.changeCount
            if statusText != "Ready" {
                statusText = "Ready"
            }
        }

        let key = "\(pasteboard.changeCount)|\(mode.rawValue)|\(tabsToSpaces)|\(returnAtEnd)"
        if key != analysisKey {
            analysisKey = key
            analysis = analyzeText(pasteboard.string(forType: .string) ?? "", mode: mode,
                                   tabsToSpaces: tabsToSpaces, returnAtEnd: returnAtEnd)
            clipboardCharacters = analysis.characterCount
            clipboardLines = analysis.lineCount
        }

        let warnings = typingWarnings(analysis: analysis, mode: mode,
                                      capsLockOn: capsLockIsOn(), delayMs: Int(delayMs))
        if warnings != clipboardWarnings {
            clipboardWarnings = warnings
        }
    }

    /// Size of the clipboard text. Never the text itself, so a copied password stays off screen.
    var clipboardSummary: String {
        if clipboardCharacters == 0 {
            return "No text on the clipboard"
        }
        let seconds = estimatedSeconds(characters: clipboardCharacters, lines: clipboardLines,
                                       delayMs: Int(delayMs))
        let lineWord = clipboardLines == 1 ? "line" : "lines"
        return "\(clipboardCharacters) characters · \(clipboardLines) \(lineWord) · \(durationLabel(seconds))"
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
