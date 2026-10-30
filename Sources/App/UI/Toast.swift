import AppKit
import SwiftUI

/// A short message near the top of the screen under the mouse, e.g. "Marked" or "Copied text".
/// It is one of our own windows, so the screen buffer never records it.
@MainActor
final class Toast {
    static let shared = Toast()

    fileprivate(set) var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ text: String, symbol: String, seconds: Double = 1.6) {
        present(ToastView(text: text, symbol: symbol), seconds: seconds)
    }

    /// Something went to the clipboard: what it is, and how to paste it, with a short preview.
    func showCopied(_ title: String, preview: String = "", symbol: String = "doc.on.clipboard") {
        var detail = L("ui.toast.pasteHint")
        if !preview.isEmpty {
            detail += ": " + preview
        }
        present(CopiedToastView(title: title, detail: detail, symbol: symbol), seconds: 3)
    }

    private func present<Content: View>(_ view: Content, seconds: Double) {
        let hosting = NSHostingView(rootView: view)
        if panel == nil {
            let newPanel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = true
            newPanel.level = .popUpMenu
            newPanel.ignoresMouseEvents = true
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            newPanel.isReleasedWhenClosed = false
            panel = newPanel
        }
        guard let panel = panel else { return }
        panel.contentView = hosting
        let size = hosting.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { screen in screen.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 60)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if Task.isCancelled { return }
            self.panel?.orderOut(nil)
        }
    }
}

extension Toast {
    /// For checks: whether a message is on screen.
    var isShowing: Bool {
        return panel?.isVisible ?? false
    }

    func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
    }
}

/// Two lines: what was copied, and how to paste it.
private struct CopiedToastView: View {
    var title: String
    var detail: String
    var symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: 0x3DD68C))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(2)
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: 440, alignment: .leading)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .fixedSize()
    }
}

private struct ToastView: View {
    var text: String
    var symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(text).lineLimit(2)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: 420)
        .background(Color.black.opacity(0.82))
        .clipShape(Capsule())
        .fixedSize()
    }
}
