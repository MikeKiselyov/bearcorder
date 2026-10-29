import AppKit
import BugbearCore
import SwiftUI

/// The five colors in the editors. They start as the usual ones; a color picked in the color
/// panel takes the first slot on the left, the others move right and the last one drops off.
@MainActor
enum RecentColors {
    static let limit = 5
    static let defaults: [AnnotationColor] = [.coral, .yellow, .blue, .green, .purple]
    static let changed = Notification.Name("BugbearRecentColorsChanged")
    private static let key = "recentAnnotationColors"
    /// Tests pick colors too; they go to the test store, not the person's palette.
    private static var store: UserDefaults { EditorMemory.defaults }

    static func load() -> [AnnotationColor] {
        var colors: [AnnotationColor] = []
        for value in store.stringArray(forKey: key) ?? [] {
            if value.hasPrefix("#"), let hex = UInt32(value.dropFirst(), radix: 16) {
                colors.append(AnnotationColor(hex: hex))
            }
        }
        if colors.isEmpty {
            return defaults
        }
        return colors
    }

    /// A picked color goes to the first slot and the others move right. While the same pick goes
    /// on (`replacingNewest`), the first slot changes instead of the others moving again.
    static func remember(_ color: AnnotationColor, replacingNewest: Bool) {
        let colors = load()
        var updated: [AnnotationColor] = []
        if replacingNewest && !colors.isEmpty {
            // Only the first slot changes; the others stay even if the drag passes over their color.
            updated = colors
            updated[0] = color
        } else {
            updated = [color]
            for existing in colors where existing != color {
                updated.append(existing)
            }
        }
        while updated.count > limit {
            updated.removeLast()
        }
        var names: [String] = []
        for kept in updated {
            names.append(String(format: "#%06X", kept.hex))
        }
        store.set(names, forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// Back to the usual five.
    static func clear() {
        store.removeObject(forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

/// The system color panel, opened from the palette. One opening is one pick: the first color
/// takes a new slot in the recent colors, the next ones while dragging update that same slot.
@MainActor
final class ColorPanelPicker: NSObject {
    static let shared = ColorPanelPicker()

    private var onPick: ((AnnotationColor) -> Void)?
    /// The editor window the panel was opened from; picks only go there, and not after it closes.
    private weak var ownerWindow: NSWindow?
    private var pickedInThisOpening = false
    private var settingColor = false
    private var pending: Task<Void, Never>?

    func open(current: AnnotationColor, onPick: @escaping (AnnotationColor) -> Void) {
        self.onPick = onPick
        ownerWindow = NSApp.keyWindow
        onPickNeedsWindow = ownerWindow != nil
        pickedInThisOpening = false
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        settingColor = true
        panel.color = current.nsColor
        settingColor = false
        panel.orderFront(nil)
    }

    /// A palette swatch was clicked: the next panel color starts a new slot.
    func endPick() {
        pickedInThisOpening = false
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        if settingColor {
            return
        }
        pick(AnnotationColor(sender.color))
    }

    /// Used by the color panel and by checks. Waits until the color settles, so dragging in the
    /// panel is one undo step and one slot.
    func pick(_ color: AnnotationColor, wait: Double = 0.25) {
        pending?.cancel()
        pending = Task { @MainActor in
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
            if Task.isCancelled {
                return
            }
            // The editor that opened the panel was closed, or another one is in front now.
            if let owner = self.ownerWindow {
                if !owner.isVisible || (NSApp.mainWindow != nil && NSApp.mainWindow !== owner) {
                    return
                }
            } else if self.onPickNeedsWindow {
                self.onPick = nil
                return
            }
            self.onPick?(color)
            RecentColors.remember(color, replacingNewest: self.pickedInThisOpening)
            self.pickedInThisOpening = true
        }
    }

    /// True when the panel was opened from a window; a pick after that window is gone is dropped.
    private var onPickNeedsWindow = false

    /// For checks: pretend the panel was opened with this handler, without a window.
    func beginForChecks(onPick: @escaping (AnnotationColor) -> Void) {
        self.onPick = onPick
        ownerWindow = nil
        onPickNeedsWindow = false
        pickedInThisOpening = false
    }
}

/// Five color slots and a round button that opens the color panel for any color.
struct ColorPalette: View {
    var selection: AnnotationColor
    var swatchSize: CGFloat = 20
    var onSelect: (AnnotationColor) -> Void

    @State private var colors: [AnnotationColor] = RecentColors.load()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(colors) { color in
                swatch(color)
            }
            Button {
                ColorPanelPicker.shared.open(current: selection) { color in
                    onSelect(color)
                }
            } label: {
                Circle()
                    .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                    .frame(width: swatchSize, height: swatchSize)
                    .overlay(Circle().stroke(Theme.borderStrong, lineWidth: 1))
                    .frame(width: swatchSize + 4, height: swatchSize + 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tip(L("editors.color.any.tip"))
            .accessibilityLabel(L("editors.color.any"))
        }
        .onReceive(NotificationCenter.default.publisher(for: RecentColors.changed)) { _ in
            colors = RecentColors.load()
        }
    }

    private func swatch(_ color: AnnotationColor) -> some View {
        Button {
            ColorPanelPicker.shared.endPick()
            onSelect(color)
        } label: {
            Circle()
                .fill(color.color)
                .frame(width: swatchSize, height: swatchSize)
                .overlay(Circle().stroke(Theme.text, lineWidth: selection == color ? 2 : 0))
                .overlay(Circle().stroke(Theme.borderStrong, lineWidth: color == .black ? 1 : 0))
                .frame(width: swatchSize + 4, height: swatchSize + 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tip(L("editors.color.swatch.tip", color.name))
        .accessibilityLabel(color.name)
    }
}

/// Fill for the mark: "No fill" or "Fill", with words so it is clear which is which. Text gets a
/// label behind it, rectangles and ellipses a see-through fill.
struct FillToggle: View {
    var isFilled: Bool
    var isEnabled: Bool
    var onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            option(filled: false, symbol: "square.dashed", title: L("editors.fill.none"), help: L("editors.fill.none.tip"))
            option(filled: true, symbol: "square.fill", title: L("editors.fill.filled"), help: L("editors.fill.filled.tip"))
        }
        .padding(3)
        .background(Theme.control)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
    }

    private func option(filled: Bool, symbol: String, title: String, help: String) -> some View {
        Button {
            onChange(filled)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(title).font(.system(size: 12, weight: isFilled == filled ? .semibold : .regular))
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(isFilled == filled ? Color(hex: 0x45484F) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tip(isEnabled ? help : L("editors.fill.disabled.tip", help))
        .accessibilityLabel(title)
    }
}

/// "− value +" for one size, with a symbol saying what the size is of. `compact` (a narrow window)
/// keeps only − and +, with the value in the tooltip.
struct SizeStepper: View {
    var value: String
    var name: String
    var symbol: String = ""
    var compact = false
    var onStep: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onStep(-1)
            } label: {
                Image(systemName: "minus").font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tip(L("editors.size.smaller.tip", name))
            .accessibilityLabel(L("editors.size.smaller", name))
            if !compact {
                HStack(spacing: 4) {
                    if !symbol.isEmpty {
                        Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                    }
                    Text(value).font(.system(size: 12, design: .monospaced))
                }
                .frame(minWidth: 40)
                .tip(L("editors.size.value.tip", name.capitalized, value))
            }
            Button {
                onStep(1)
            } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tip(L("editors.size.bigger.tip", name))
            .accessibilityLabel(L("editors.size.bigger", name))
        }
        .padding(.horizontal, 3)
        .background(Theme.control)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

/// Delete and Backspace remove the selected mark anywhere in an editor window, not only while
/// the canvas has focus, except while typing in a text field.
struct DeleteKeyMonitor: NSViewRepresentable {
    var onDelete: () -> Bool
    /// ⌘V anywhere in the window; return false to let the key go on (e.g. no picture to paste).
    var onPaste: (() -> Bool)? = nil

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onDelete = onDelete
        view.onPaste = onPaste
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onDelete = onDelete
        view.onPaste = onPaste
    }

    final class MonitorView: NSView {
        var onDelete: (() -> Bool)?
        var onPaste: (() -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let existing = monitor {
                NSEvent.removeMonitor(existing)
                monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }
                let handled = MainActor.assumeIsolated {
                    self.handle(event)
                }
                if handled {
                    return nil
                }
                return event
            }
        }

        @MainActor
        private func handle(_ event: NSEvent) -> Bool {
            guard event.window === window else { return false }
            let commandOnly = event.modifierFlags.intersection([.command, .option, .control, .shift]) == [.command]
            if commandOnly && LatinKeys.key(forKeyCode: event.keyCode, typed: event.charactersIgnoringModifiers ?? "") == "v" {
                if window?.firstResponder is NSText {
                    return false
                }
                return onPaste?() ?? false
            }
            guard event.keyCode == 51 || event.keyCode == 117 else { return false }
            let flags = event.modifierFlags.intersection([.command, .option, .control])
            if !flags.isEmpty {
                return false
            }
            // Typing: let the text field delete characters.
            if window?.firstResponder is NSText {
                return false
            }
            return onDelete?() ?? false
        }
    }
}
