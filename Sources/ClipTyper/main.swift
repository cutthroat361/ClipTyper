// ClipTyper — menu-bar app that types the clipboard as keystrokes.
//
// Built for remote sessions (Windows App / RDP, ScreenConnect, Datto RMM) where paste is
// blocked or truncated. Press the global shortcut and the clipboard is typed into whatever
// window has focus.
//
// Where things live:
//   main.swift             entry point (this file)
//   AppDelegate.swift      menu-bar icon and the panel that opens from it
//   AppModel.swift         settings, the shortcut, and the "type the clipboard" flow
//   PanelView.swift        the panel's SwiftUI layout
//   HUD.swift              the small on-screen progress bar
//   Typer.swift            posts the actual key events
//   HotKeyCenter.swift     global shortcuts
//   Shortcut.swift         shortcut model and its display name
//   KeyMap.swift           which physical key produces which character
//   TextPreparation.swift  clean-up of the text, pre-typing checks and estimates
//
// Build: ./build.sh   (needs Xcode Command Line Tools). See README.md.

import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// .accessory = no Dock icon and no main menu; the app lives in the menu bar only.
app.setActivationPolicy(.accessory)
app.run()
