import Cocoa
import SwiftUI

/// Owns the menu-bar icon, the panel that opens from it, and the on-screen HUD.
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let model = AppModel()
    private let popover = NSPopover()
    private let hud = HUDController()
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
        model.onHUDChange = { [weak self] content in
            if let content = content {
                self?.hud.show(content)
            } else {
                self?.hud.hide()
            }
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
        model.cancelConfirmation()
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

        // Keep clipboard size, warnings and permission state current while the panel is open.
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
