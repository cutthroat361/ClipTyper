import Cocoa
import SwiftUI

/// What the on-screen HUD shows.
enum HUDContent: Equatable {
    /// Typing in progress, 0...1.
    case progress(Double)
    /// Something to check before typing, with a line saying how to continue or cancel.
    case warning(lines: [String], hint: String)
    /// A short note such as "Done" or "Stopped".
    case message(String)
}

/// The small dark pill at the top of the screen.
///
/// It often lands on top of a window's title bar or a browser's tab strip, so it is opaque
/// and outlined: a translucent pill let the tab titles show through and was easy to miss.
struct HUDView: View {
    let content: HUDContent

    private let barWidth: CGFloat = 130
    private let barColor = Color(red: 0.33, green: 0.62, blue: 1.0)

    var body: some View {
        pill
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(white: 0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.38), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.45), radius: 9, x: 0, y: 3)
            .padding(16)   // room for the shadow
            // The window is larger than the pill and fully transparent; pin the pill to its top.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var pill: some View {
        switch content {
        case .progress(let value):
            HStack(spacing: 10) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.24))
                    Capsule().fill(barColor)
                        .frame(width: max(5, barWidth * CGFloat(min(max(value, 0), 1))))
                }
                .frame(width: barWidth, height: 5)
                Text("\(Int(value * 100))%")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
                Text("esc to stop")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.7))
            }

        case .warning(let lines, let hint):
            VStack(spacing: 5) {
                ForEach(lines, id: \.self) { line in
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow)
                        Text(line)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                }
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.7))
                    .lineLimit(1)
            }

        case .message(let text):
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
    }
}

/// Owns the HUD window: a transparent, click-through panel that never takes keyboard focus,
/// so it can sit on top of the remote session while keys are being typed into it.
///
/// Every appearance gets a new window. Reusing one window (fade out, order out, then order
/// front again) left it invisible when it was shown again about a second after hiding.
final class HUDController {
    private var panel: NSPanel?
    private var hosting: NSHostingView<HUDView>?
    /// The previous window while it fades out.
    private var fading: NSPanel?
    private let size = NSSize(width: 560, height: 150)

    func show(_ content: HUDContent) {
        if panel != nil, let hosting = hosting {
            hosting.rootView = HUDView(content: content)
            return
        }
        // Do not let the previous window finish its fade underneath the new one.
        fading?.orderOut(nil)
        fading = nil

        let panel = makePanel(content)
        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        guard let closing = panel else { return }
        panel = nil
        hosting = nil
        fading?.orderOut(nil)
        fading = closing
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            closing.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            closing.orderOut(nil)
            if self?.fading === closing {
                self?.fading = nil
            }
        })
    }

    private func makePanel(_ content: HUDContent) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false      // the app is never "active"; stay visible anyway
        panel.isReleasedWhenClosed = false
        // Show on every Space and on top of full-screen apps such as a full-screen RDP session.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hosting = NSHostingView(rootView: HUDView(content: content))
        hosting.sizingOptions = []           // keep the window at the size set here
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.hosting = hosting
        return panel
    }

    /// Top centre of the screen the mouse pointer is on, just below the menu bar.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let underMouse = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        guard let screen = underMouse ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.maxY - size.height + 6)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
