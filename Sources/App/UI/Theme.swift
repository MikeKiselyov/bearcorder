import AppKit
import SwiftUI

/// Colors of the Aurora look: glass surfaces over a soft plum and coral gradient, coral accent.
/// Surfaces are see-through on purpose, so the window's `AuroraBackground` shows through them.
enum Theme {
    /// The darkest base under the gradient, for places that need a solid color.
    static let background = Color(hex: 0x100D14)
    /// What a window's gradient fades into; solid, for AppKit and pictures.
    static let window = Color(hex: 0x16131B)
    static let panel = Color.white.opacity(0.06)
    static let sidebar = Color.white.opacity(0.035)
    static let well = Color.black.opacity(0.28)
    static let canvas = Color.black.opacity(0.22)
    static let control = Color.white.opacity(0.09)
    static let controlSelected = Color.white.opacity(0.16)
    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.14)
    static let text = Color(hex: 0xECEDEE)
    static let textSecondary = Color(hex: 0xA6A9AF)
    static let textTertiary = Color(hex: 0x5F636B)
    static let accent = Color(hex: 0xFF6B4A)
    static let accentText = Color(hex: 0x1A0B06)
    static let accentSoft = Color(hex: 0xFF8C70)
    /// The coral gradient of main buttons, light at the top left.
    static let accentGradient = LinearGradient(colors: [Color(hex: 0xFF8C70), Color(hex: 0xFF5A36)], startPoint: .topLeading, endPoint: .bottomTrailing)
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

/// The main action: a coral gradient that glows.
struct AccentButtonStyle: ButtonStyle {
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        var opacity = 1.0
        if configuration.isPressed {
            opacity = 0.8
        } else if !isEnabled {
            opacity = 0.4
        }
        return configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(Theme.accentGradient)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .shadow(color: Theme.accent.opacity(isEnabled ? 0.35 : 0), radius: 9, y: 4)
            .opacity(opacity)
    }
}

/// A big round action, like Clean or Continue.
struct GlowButtonStyle: ButtonStyle {
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        var opacity = 1.0
        if configuration.isPressed {
            opacity = 0.85
        } else if !isEnabled {
            opacity = 0.4
        }
        return configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 22)
            .frame(height: 38)
            .background(Theme.accentGradient)
            .clipShape(Capsule())
            .shadow(color: Theme.accent.opacity(isEnabled ? 0.45 : 0), radius: 13, y: 6)
            .opacity(opacity)
    }
}

/// A glass button for everything that is not the main action.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(configuration.isPressed ? Theme.controlSelected : Theme.control)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 9))
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
            ToolIcon(name: systemImage, size: 15)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? Theme.accentText : tint)
                .frame(width: 34, height: 34)
                .background(isSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tip(help)
        .accessibilityLabel(help)
    }
}

/// An SF Symbol, or one drawn here for a tool SF Symbols has nothing for.
struct ToolIcon: View {
    /// An arrow with "Aa" at its tail, like the mark the tool draws.
    static let arrowWithText = "custom.arrow-with-text"

    let name: String
    var size: CGFloat

    var body: some View {
        if name == ToolIcon.arrowWithText {
            ZStack(alignment: .topLeading) {
                Text(verbatim: "Aa")
                    .font(.system(size: size * 0.62, weight: .bold))
                    .offset(x: -size * 0.1, y: size * 0.42)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: size * 0.72, weight: .semibold))
                    .offset(x: size * 0.62, y: -size * 0.06)
            }
            .frame(width: size * 1.3, height: size * 1.2, alignment: .topLeading)
            .accessibilityHidden(true)
        } else {
            Image(systemName: name)
        }
    }
}

/// Segmented control styled like the mockups (dark well with a raised selection).
struct PillPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    /// An SF Symbol shown before each label, when given.
    var symbol: ((Value) -> String)? = nil

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    HStack(spacing: 6) {
                        if let symbol = symbol {
                            Image(systemName: symbol(option))
                        }
                        Text(label(option))
                    }
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.text : Color(hex: 0xC9CBD0))
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(isSelected ? Color.white.opacity(0.18) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.control)
        .clipShape(RoundedRectangle(cornerRadius: 9))
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
            .glassCard(cornerRadius: 12)
    }

    /// A see-through card with a thin light edge, the main surface of the Aurora look.
    func glassCard(cornerRadius: CGFloat = 14) -> some View {
        self
            .background(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// The window's gradient behind the view.
    func auroraBackground() -> some View {
        self.background(AuroraBackground())
    }
}

/// The soft gradient behind every window and the menu: plum from the top right, violet from the
/// bottom left, over a near-black base.
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            Theme.window
            RadialGradient(colors: [Color(hex: 0x5B2A4E), Color(hex: 0x5B2A4E, alpha: 0)], center: UnitPoint(x: 0.9, y: -0.1), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(hex: 0x2E1F4A), Color(hex: 0x2E1F4A, alpha: 0)], center: UnitPoint(x: 0, y: 1.1), startRadius: 0, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

/// The colors of icon tiles: each section and action has its own.
enum TileTint {
    case coral, pink, purple, blue, green, yellow, gray, teal, red

    var colors: [Color] {
        switch self {
        case .coral: return [Color(hex: 0xFF8C70), Color(hex: 0xE2452A)]
        case .pink: return [Color(hex: 0xFF9BC6), Color(hex: 0xD9488A)]
        case .purple: return [Color(hex: 0xDDB2F5), Color(hex: 0x9B5FC9)]
        case .blue: return [Color(hex: 0x9CC5FF), Color(hex: 0x4C83E0)]
        case .green: return [Color(hex: 0x5BE7A9), Color(hex: 0x1F9E68)]
        case .yellow: return [Color(hex: 0xFFDA70), Color(hex: 0xE0A21C)]
        case .gray: return [Color(hex: 0x9BA3AE), Color(hex: 0x5E6670)]
        case .teal: return [Color(hex: 0x7DE3E0), Color(hex: 0x1E9E9A)]
        case .red: return [Color(hex: 0xFF7A7A), Color(hex: 0xC62828)]
        }
    }

    /// The middle of the gradient, for a glow or a dot.
    var color: Color {
        return colors[1]
    }
}

/// A white symbol on a rounded colored square with a light top edge, like the icons in CleanMyMac.
struct IconTile: View {
    let systemImage: String
    let tint: TileTint
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3)
            .fill(LinearGradient(colors: tint.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0)], startPoint: .top, endPoint: .center), lineWidth: 1)
            )
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .shadow(color: Color.black.opacity(0.25), radius: 4, y: 2)
            .accessibilityHidden(true)
    }
}
