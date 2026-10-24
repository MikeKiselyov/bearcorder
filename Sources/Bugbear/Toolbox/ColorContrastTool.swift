import AppKit
import BugbearCore
import SwiftUI

/// Picks a color anywhere on screen with the system loupe.
@MainActor
enum ColorPick {
    static func pick() async -> RGBAColor? {
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
        Toast.shared.show("Copied \(hex)", symbol: "eyedropper")
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
                    colorInput("Text", value: $foreground, parsed: text)
                    Button {
                        let swap = foreground
                        foreground = background
                        background = swap
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 34)
                    .help("Swap")
                    colorInput("Background", value: $background, parsed: back)
                }
                if let textColor = text, let backColor = back {
                    result(Contrast.verdict(foreground: textColor, background: backColor), text: textColor, back: backColor)
                } else {
                    Text("Enter colors as #RRGGBB, rgb(…) or hsl(…), or pick them from the screen.")
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
                Button {
                    Task {
                        if let picked = await ColorPick.pick() {
                            value.wrappedValue = ColorConverter.formats(picked).hex
                        }
                    }
                } label: {
                    Image(systemName: "eyedropper")
                }
                .help("Pick from the screen")
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
                Text("contrast ratio").foregroundStyle(Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("The quick brown fox, 14 pt")
                    .font(.system(size: 14))
                Text("Large heading, 24 pt")
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
                    Text("AA").font(.system(size: 12, weight: .semibold))
                    Text("AAA").font(.system(size: 12, weight: .semibold))
                }
                GridRow {
                    Text("Normal text").font(.system(size: 12))
                    badge(verdict.passesAANormal, need: "4.5")
                    badge(verdict.passesAAANormal, need: "7")
                }
                GridRow {
                    Text("Large text (18 pt, or 14 pt bold)").font(.system(size: 12))
                    badge(verdict.passesAALarge, need: "3")
                    badge(verdict.passesAAALarge, need: "4.5")
                }
                GridRow {
                    Text("Icons, borders, focus rings").font(.system(size: 12))
                    badge(verdict.passesUIComponents, need: "3")
                    Text("")
                }
            }
        }
    }

    private func badge(_ passes: Bool, need: String) -> some View {
        Label(passes ? "Pass" : "Fail · needs \(need)", systemImage: passes ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(passes ? Theme.success : Theme.warning)
    }
}
