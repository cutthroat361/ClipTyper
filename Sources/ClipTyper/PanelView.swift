import Cocoa
import SwiftUI

let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

/// A rounded, slightly tinted box that groups related controls in the panel.
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

/// The current shortcut, drawn like a key.
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

/// The panel that opens from the menu-bar icon.
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
            ForEach(model.clipboardWarnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            Toggle("Clear clipboard after typing", isOn: $model.clearClipboardAfter)
            Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin },
                                                    set: { model.setLaunchAtLogin($0) }))
        }
    }

    private var footer: some View {
        HStack {
            Text("ClipTyper \(appVersion) · Esc stops typing.")
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
