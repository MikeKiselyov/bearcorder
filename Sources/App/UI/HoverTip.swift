import AppKit
import SwiftUI

/// Tooltips drawn by the app itself. macOS shows `.help` tooltips only while the app is active, and
/// the menu bar panel never makes the app active, so many of them never appeared. This one shows a
/// small panel next to the pointer after a short hover, in every window.
@MainActor
final class HoverTip {
    static let shared = HoverTip()
    static let delay: Double = 0.6
    static let fontSize: CGFloat = 12
    static let maxTextWidth: CGFloat = 280
    static let horizontalPadding: CGFloat = 9
    static let verticalPadding: CGFloat = 6

    private var panel: NSPanel?
    private var showTask: Task<Void, Never>?
    private var owner: UUID?
    private var eventMonitor: Any?

    /// The pointer entered (`inside` true) or left a view with a tip.
    func hover(_ text: String, owner id: UUID, inside: Bool) {
        if inside {
            if owner != id {
                // Moving straight to another view: the old tip goes at once.
                panel?.orderOut(nil)
            }
            owner = id
            showTask?.cancel()
            showTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(HoverTip.delay * 1_000_000_000))
                if Task.isCancelled || self.owner != id {
                    return
                }
                self.show(text)
            }
        } else if owner == id {
            hide()
        }
    }

    func hide() {
        showTask?.cancel()
        showTask = nil
        owner = nil
        panel?.orderOut(nil)
    }

    /// Panel size and text width for a tip. It comes from the wrapped text itself: the fitting size
    /// of the SwiftUI view cut off the last line of long tips.
    static func layout(for text: String) -> (size: CGSize, textWidth: CGFloat) {
        let bounds = (text as NSString).boundingRect(with: CGSize(width: maxTextWidth, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: fontSize)])
        let textWidth = ceil(bounds.width) + 2
        let textHeight = ceil(bounds.height) + 4
        let size = CGSize(width: textWidth + horizontalPadding * 2, height: textHeight + verticalPadding * 2)
        return (size: size, textWidth: textWidth)
    }

    private func show(_ text: String) {
        if panel == nil {
            let newPanel = HoverTipPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = true
            // Above the menu bar panel and the editor windows.
            newPanel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
            newPanel.ignoresMouseEvents = true
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            newPanel.isReleasedWhenClosed = false
            panel = newPanel
        }
        if eventMonitor == nil {
            // A click, a key or scrolling means the person moved on.
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { event in
                MainActor.assumeIsolated {
                    HoverTip.shared.hide()
                }
                return event
            }
        }
        guard let panel = panel else { return }
        let layout = HoverTip.layout(for: text)
        let size = layout.size
        let hosting = NSHostingView(rootView: HoverTipView(text: text, textWidth: layout.textWidth))
        hosting.frame = CGRect(origin: .zero, size: size)
        panel.contentView = hosting
        let mouse = NSEvent.mouseLocation
        var origin = CGPoint(x: mouse.x + 10, y: mouse.y - size.height - 20)
        let screen = NSScreen.screens.first { item in item.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            if origin.x + size.width > visible.maxX {
                origin.x = visible.maxX - size.width - 4
            }
            if origin.y < visible.minY {
                // No room below the pointer: show it above.
                origin.y = mouse.y + 16
            }
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }
}

/// Named so automation can find it next to the system tooltip windows.
final class HoverTipPanel: NSPanel {}

struct HoverTipView: View {
    var text: String
    var textWidth: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: HoverTip.fontSize))
            .foregroundStyle(Color.white.opacity(0.92))
            .multilineTextAlignment(.leading)
            .frame(width: textWidth, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, HoverTip.horizontalPadding)
            .padding(.vertical, HoverTip.verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(hex: 0x2A2C31))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

extension View {
    /// A tooltip that works in every window of the app, the menu bar panel too. VoiceOver reads it as a hint.
    func tip(_ text: String) -> some View {
        modifier(HoverTipModifier(text: text))
    }
}

private struct HoverTipModifier: ViewModifier {
    let text: String
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            // AppKit tracking, not .onHover: SwiftUI hover only works while the app is active, and
            // the menu bar panel is used with another app in front.
            .overlay(HoverTracker { inside in
                HoverTip.shared.hover(text, owner: id, inside: inside)
            })
            .onDisappear {
                HoverTip.shared.hover(text, owner: id, inside: false)
            }
            .accessibilityHint(text)
    }
}

/// A see-through view that reports the pointer entering and leaving, in any app state. Clicks go
/// through to the view below.
private struct HoverTracker: NSViewRepresentable {
    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onHover = onHover
    }

    final class TrackingView: NSView {
        var onHover: ((Bool) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil
        }

        // One area for the view's whole life: .inVisibleRect follows its size, so it is not rebuilt on
        // every layout (the recording bar redraws all the time).
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if trackingAreas.isEmpty {
                addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
            }
        }

        override func mouseEntered(with event: NSEvent) {
            onHover?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(false)
        }
    }
}
