import AppKit
import SwiftUI

/// The last colors picked in the color panel, newest first, so they are one click away.
@MainActor
enum RecentColors {
    static let limit = 4
    private static let key = "recentAnnotationColors"

    static func load() -> [AnnotationColor] {
        var colors: [AnnotationColor] = []
        for value in UserDefaults.standard.stringArray(forKey: key) ?? [] {
            if value.hasPrefix("#"), let hex = UInt32(value.dropFirst(), radix: 16) {
                colors.append(AnnotationColor(hex: hex))
            }
        }
        return colors
    }

    /// Puts a picked color first. Palette colors are always shown, so they are not kept.
    static func remember(_ color: AnnotationColor) {
        if color.isInPalette {
            return
        }
        var colors = [color]
        for existing in load() where existing != color {
            colors.append(existing)
        }
        while colors.count > limit {
            colors.removeLast()
        }
        var names: [String] = []
        for kept in colors {
            names.append(kept.name)
        }
        UserDefaults.standard.set(names, forKey: key)
    }
}

/// Palette swatches, then the last picked colors, then a well that opens the color panel.
struct ColorPalette: View {
    var selection: AnnotationColor
    var swatchSize: CGFloat = 20
    var onSelect: (AnnotationColor) -> Void

    @State private var recent: [AnnotationColor] = RecentColors.load()
    @State private var pickerColor: Color = .white
    @State private var pendingPick: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationColor.palette) { color in
                swatch(color)
            }
            if !recent.isEmpty {
                Rectangle().fill(Theme.borderStrong).frame(width: 1, height: swatchSize - 4).padding(.horizontal, 2)
                ForEach(recent) { color in
                    swatch(color)
                }
            }
            ColorPicker("", selection: Binding(get: { pickerColor }, set: { value in pick(value) }), supportsOpacity: false)
                .labelsHidden()
                .frame(width: swatchSize + 8)
                .help("Any color: opens the color panel. The last \(RecentColors.limit) picked colors stay next to the palette")
                .accessibilityLabel("Pick any color")
        }
        .onAppear {
            pickerColor = selection.color
        }
    }

    private func swatch(_ color: AnnotationColor) -> some View {
        Button {
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
        .help(swatchHelp(color))
        .accessibilityLabel(color.name)
    }

    private func swatchHelp(_ color: AnnotationColor) -> String {
        if color.isInPalette {
            return "Color: \(color.name). Used for new marks and the selected one"
        }
        return "Recently picked color \(color.name)"
    }

    /// The color panel reports every step while you drag in it; the color is used once it settles.
    private func pick(_ value: Color) {
        pickerColor = value
        pendingPick?.cancel()
        pendingPick = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled {
                return
            }
            let picked = AnnotationColor(NSColor(value))
            onSelect(picked)
            RecentColors.remember(picked)
            recent = RecentColors.load()
        }
    }
}

/// Two buttons: transparent background or filled. Text gets a label behind it, rectangles and
/// ellipses a see-through fill.
struct FillToggle: View {
    var isFilled: Bool
    var isEnabled: Bool
    var onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            option(filled: false, symbol: "square.dashed", help: "Transparent: text without a label, shapes as outlines only")
            option(filled: true, symbol: "square.fill", help: "Filled: text on a colored label, shapes with a see-through fill")
        }
        .padding(3)
        .background(Theme.control)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
    }

    private func option(filled: Bool, symbol: String, help: String) -> some View {
        Button {
            onChange(filled)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 26, height: 26)
                .background(isFilled == filled ? Color(hex: 0x45484F) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isEnabled ? help : "\(help). Works with Text, Rectangle and Ellipse")
        .accessibilityLabel(filled ? "Filled" : "Transparent")
    }
}

/// "− value +" for a size, with the value in between.
struct SizeStepper: View {
    var value: String
    var name: String
    var onStep: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onStep(-1)
            } label: {
                Image(systemName: "minus").font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Smaller \(name) (-)")
            .accessibilityLabel("Smaller \(name)")
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .frame(minWidth: 26)
                .help("\(name.capitalized): \(value)")
            Button {
                onStep(1)
            } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Bigger \(name) (+)")
            .accessibilityLabel("Bigger \(name)")
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

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onDelete = onDelete
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onDelete = onDelete
    }

    final class MonitorView: NSView {
        var onDelete: (() -> Bool)?
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
            guard event.window === window, event.keyCode == 51 || event.keyCode == 117 else { return false }
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
