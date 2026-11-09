<p align="center">
  <img src="docs/icon.png" width="128" alt="ClipTyper icon">
</p>

<h1 align="center">ClipTyper</h1>

<p align="center">
  A macOS menu-bar app that types your clipboard as keystrokes.<br>
  For remote sessions where paste is blocked, truncated or unreliable.
</p>

<p align="center">
  <img src="docs/panel.png" width="334" alt="ClipTyper panel">
</p>

## What it is for

Remote-control tools often refuse to paste, or cut the paste short. ClipTyper works around
that: copy a script on the Mac, click into the remote window, press a shortcut, and the text
is typed in key by key as if you had typed it yourself.

Tested with:

- Windows App (Microsoft Remote Desktop / RDP)
- Datto RMM web remote
- ScreenConnect

## Features

- Global shortcut (default ⌃⌥V) that you can rebind to any key combination or a single F-key
- Menu-bar panel with an on/off switch, clipboard size, speed and mode controls
- Progress shown in the menu bar while typing; press the shortcut again or click the icon to stop
- Two typing modes:
  - **Key presses**: real US-layout key presses. This is the mode for RDP, ScreenConnect and Datto
  - **Unicode**: sends characters directly, in any language, for Mac apps and VNC
- Converts tabs to spaces, so Tab does not trigger autocomplete in PowerShell
- Replaces curly quotes and long dashes with their plain forms in Key presses mode
- Launch at login
- No network access, and the clipboard text is never shown or stored

## Install

Requires macOS 13 or newer.

### Download

For Apple silicon Macs (M1 and later):

1. Download the zip from the [latest release](https://github.com/cutthroat361/ClipTyper/releases/latest) and unzip it.
2. Move `ClipTyper.app` to the Applications folder.
3. The app is not notarized by Apple, so run this once in Terminal:
   ```
   xattr -dr com.apple.quarantine /Applications/ClipTyper.app
   ```
4. Open ClipTyper.

### Build from source

Works on Intel and Apple silicon. Needs the Xcode Command Line Tools (`xcode-select --install`).

```
git clone https://github.com/cutthroat361/ClipTyper.git
cd ClipTyper
./build.sh
```

The script compiles the app, installs it into `/Applications` and starts it.

### Permission

On first start, allow ClipTyper under **System Settings > Privacy & Security > Accessibility**.
macOS requires this permission for any app that presses keys for you.

## Use

1. Copy the text.
2. Click into the remote window (Notepad, PowerShell, a login field).
3. Press ⌃⌥V.

Click the keyboard icon in the menu bar to change the shortcut, the speed or the mode.

## Things to know

- **Remote keyboard layout must be English (US)** in Key presses mode. ClipTyper presses
  physical keys, and the remote machine decides which character each key produces.
- **Characters with no key on a US keyboard are skipped** in Key presses mode (Cyrillic,
  emoji and so on). The panel reports how many were skipped.
- **Dropped characters on a slow link**: raise the per-character delay to 15–20 ms.
- **Editors that auto-indent or auto-close brackets** (PowerShell ISE, VS Code) will change
  typed code. Notepad and the console do not.
- **F-keys on a MacBook** only act as F-keys with Fn held, unless "Use F1, F2, etc. keys as
  standard function keys" is turned on in Keyboard settings.
- **The shortcut is global**: the combination you choose no longer reaches other apps or the
  remote session while ClipTyper is switched on.

## Keeping the permission across rebuilds

By default the app is ad-hoc signed, so macOS treats every build as a new app and the
Accessibility permission has to be removed and added again after each rebuild.

To avoid that, create a local signing certificate once:

1. Open **Keychain Access > Certificate Assistant > Create a Certificate…**
2. Name: `ClipTyper Local`, Identity Type: Self-Signed Root, Certificate Type: Code Signing
3. Run `./build.sh` again. It finds the certificate by name and signs with it.

## Building a release zip

```
./build.sh --zip
```

This also writes `dist/ClipTyper-<version>.zip`. The app is not notarized by Apple, so on
another Mac it has to be released from quarantine after unzipping:

```
xattr -dr com.apple.quarantine /Applications/ClipTyper.app
```

## Credits

Inspired by [ArbenP/TypeClipboard](https://github.com/ArbenP/TypeClipboard) for macOS and
[jlaundry/TypeClipboard](https://github.com/jlaundry/TypeClipboard) for Windows.
