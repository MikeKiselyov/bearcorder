import AppKit
import AppCore
import SwiftUI

/// Picks a color anywhere on screen with the system loupe.
@MainActor
enum ColorPick {
    /// The system loupe is open.
    private(set) static var isPicking = false

    static func pick() async -> RGBAColor? {
        isPicking = true
        defer { isPicking = false }
        return await withCheckedContinuation { continuation in
            NSColorSampler().show { picked in
                guard let color = picked?.usingColorSpace(.sRGB) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: RGBAColor(red: Double(color.redComponent), green: Double(color.greenComponent), blue: Double(color.blueComponent), alpha: Double(color.alphaComponent)))
            }
        }
    }

    /// Menu bar "Pick a color": the hex code goes to the clipboard.
    static func pickAndCopy() async {
        guard let color = await pick() else { return }
        let hex = ColorConverter.formats(color).hex
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
        Toast.shared.showCopied(L("toolbox.color.copied"), preview: hex, symbol: "eyedropper")
    }
}

struct ColorContrastTool: View {
    @State private var foreground = "#777777"
    @State private var background = "#FFFFFF"

    var body: some View {
        let text = ColorConverter.parse(foreground)
        let back = ColorConverter.parse(background)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    colorInput(L("toolbox.contrast.text"), value: $foreground, parsed: text)
                    Button {
                        let swap = foreground
                        foreground = background
                        background = swap
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 34)
                    .accessibilityLabel(L("toolbox.contrast.swap"))
                    .tip(L("toolbox.contrast.swap.tip"))
                    colorInput(L("toolbox.contrast.background"), value: $background, parsed: back)
                }
                if let textColor = text, let backColor = back {
                    result(Contrast.verdict(foreground: textColor, background: backColor), text: textColor, back: backColor)
                } else {
                    Text(L("toolbox.contrast.enterColors"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.warning)
                }
            }
            .padding(16)
        }
    }

    private func colorInput(_ title: String, value: Binding<String>, parsed: RGBAColor?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(swatch(parsed))
                    .frame(width: 34, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderStrong, lineWidth: 1))
                TextField("#RRGGBB", text: value)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .accessibilityLabel(L("toolbox.contrast.colorField", title))
                    .tip(L("toolbox.contrast.colorField.tip", title))
                Button {
                    Task {
                        if let picked = await ColorPick.pick() {
                            value.wrappedValue = ColorConverter.formats(picked).hex
                        }
                    }
                } label: {
                    Image(systemName: "eyedropper")
                }
                .accessibilityLabel(L("toolbox.contrast.pick", title.lowercased()))
                .tip(L("toolbox.contrast.pick.tip", title.lowercased()))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func swatch(_ color: RGBAColor?) -> Color {
        guard let value = color else { return Color.clear }
        return Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }

    private func result(_ verdict: Contrast.Verdict, text: RGBAColor, back: RGBAColor) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%.2f : 1", verdict.ratio))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(L("toolbox.contrast.ratio")).foregroundStyle(Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(L("toolbox.contrast.sample.normal"))
                    .font(.system(size: 14))
                Text(L("toolbox.contrast.sample.large"))
                    .font(.system(size: 24, weight: .semibold))
            }
            .foregroundStyle(swatch(text))
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(swatch(back))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("")
                    Text(L("toolbox.contrast.level.aa")).font(.system(size: 12, weight: .semibold))
                    Text(L("toolbox.contrast.level.aaa")).font(.system(size: 12, weight: .semibold))
                }
                GridRow {
                    Text(L("toolbox.contrast.row.normal")).font(.system(size: 12))
                    badge(verdict.passesAANormal, need: "4.5")
                    badge(verdict.passesAAANormal, need: "7")
                }
                GridRow {
                    Text(L("toolbox.contrast.row.large")).font(.system(size: 12))
                    badge(verdict.passesAALarge, need: "3")
                    badge(verdict.passesAAALarge, need: "4.5")
                }
                GridRow {
                    Text(L("toolbox.contrast.row.ui")).font(.system(size: 12))
                    badge(verdict.passesUIComponents, need: "3")
                    Text("")
                }
            }
        }
    }

    private func badge(_ passes: Bool, need: String) -> some View {
        Label(passes ? L("toolbox.contrast.pass") : L("toolbox.contrast.fail", need), systemImage: passes ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(passes ? Theme.success : Theme.warning)
    }
}
