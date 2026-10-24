import Foundation

/// WCAG 2.x contrast between a text color and its background.
public enum Contrast {
    public struct Verdict: Equatable {
        public var ratio: Double
        /// 4.5:1 normal text, 3:1 large text (18 pt, or 14 pt bold).
        public var passesAANormal: Bool
        public var passesAALarge: Bool
        /// 7:1 normal text, 4.5:1 large text.
        public var passesAAANormal: Bool
        public var passesAAALarge: Bool
        /// 3:1 for icons, borders and focus rings (WCAG 1.4.11).
        public var passesUIComponents: Bool
    }

    /// Relative luminance of an sRGB color, 0 (black) to 1 (white).
    public static func luminance(_ color: RGBAColor) -> Double {
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    static func linear(_ channel: Double) -> Double {
        if channel <= 0.04045 {
            return channel / 12.92
        }
        return pow((channel + 0.055) / 1.055, 2.4)
    }

    /// From 1:1 (same color) to 21:1 (black on white). A see-through text color is blended over the background first.
    public static func ratio(foreground: RGBAColor, background: RGBAColor) -> Double {
        var text = foreground
        if foreground.alpha < 1 {
            text = RGBAColor(
                red: foreground.red * foreground.alpha + background.red * (1 - foreground.alpha),
                green: foreground.green * foreground.alpha + background.green * (1 - foreground.alpha),
                blue: foreground.blue * foreground.alpha + background.blue * (1 - foreground.alpha)
            )
        }
        let lighter = max(luminance(text), luminance(background))
        let darker = min(luminance(text), luminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    public static func verdict(foreground: RGBAColor, background: RGBAColor) -> Verdict {
        let value = ratio(foreground: foreground, background: background)
        // WCAG compares the unrounded ratio.
        return Verdict(
            ratio: value,
            passesAANormal: value >= 4.5,
            passesAALarge: value >= 3,
            passesAAANormal: value >= 7,
            passesAAALarge: value >= 4.5,
            passesUIComponents: value >= 3
        )
    }
}
