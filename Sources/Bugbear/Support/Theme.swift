import AppKit
import SwiftUI

/// Colors from the design canvas (dark, coral accent).
enum Theme {
    static let background = Color(hex: 0x0E0F11)
    static let window = Color(hex: 0x1B1C1F)
    static let panel = Color(hex: 0x232428)
    static let sidebar = Color(hex: 0x18191C)
    static let well = Color(hex: 0x151618)
    static let canvas = Color(hex: 0x131416)
    static let control = Color(hex: 0x2B2D31)
    static let controlSelected = Color(hex: 0x3B3E45)
    static let border = Color(hex: 0x2E3034)
    static let borderStrong = Color(hex: 0x3A3C41)
    static let text = Color(hex: 0xECEDEE)
    static let textSecondary = Color(hex: 0xA6A9AF)
    static let textTertiary = Color(hex: 0x5F636B)
    static let accent = Color(hex: 0xFF6B4A)
    static let accentText = Color(hex: 0x1A0B06)
    static let accentSoft = Color(hex: 0xFF8C70)
    static let link = Color(hex: 0x8AB8FF)
    static let success = Color(hex: 0x3DD68C)
    static let warning = Color(hex: 0xFFC93C)
    static let syntaxKey = Color(hex: 0x8AB8FF)
    static let syntaxString = Color(hex: 0x3DD68C)
    static let syntaxNumber = Color(hex: 0xFFC93C)
    static let syntaxKeyword = Color(hex: 0xC792EA)

    static let mono = Font.system(size: 12, design: .monospaced)
    static let sectionLabel = Font.system(size: 11, weight: .semibold)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// Uppercase tracked label used for panel sections ("ENVIRONMENT · AUTO").
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.sectionLabel)
            .tracking(0.7)
            .foregroundStyle(Theme.textSecondary)
    }
}

struct AccentButtonStyle: ButtonStyle {
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.4)))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(configuration.isPressed ? Theme.controlSelected : Theme.control)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderStrong, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

/// Icon-only toolbar button with a selected state.
struct ToolButton: View {
    let systemImage: String
    let help: String
    var isSelected = false
    var tint: Color = Theme.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? Theme.accentSoft : tint)
                .frame(width: 34, height: 34)
                .background(isSelected ? Theme.controlSelected : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Segmented control styled like the mockups (dark well with a raised selection).
struct PillPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.text : Color(hex: 0xC9CBD0))
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(isSelected ? Color(hex: 0x45484F) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.control)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

/// Toggle row with the coral switch from the mockups.
struct SettingToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title).font(.system(size: 13))
        }
        .toggleStyle(.switch)
        .tint(Theme.accent)
        .controlSize(.small)
    }
}

extension View {
    func panelCard() -> some View {
        self
            .padding(12)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
