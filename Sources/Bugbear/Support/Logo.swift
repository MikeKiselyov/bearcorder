import AppKit
import SwiftUI

/// The Bugbear logo: a bear peeking over a sesame bun with a bug on it, as one flat shape.
/// Drawn in code so the menu bar glyph, the in-app logo and the app icon are the same picture.
enum Logo {
    static let tileTop = NSColor(hex: 0x3A3C41)
    static let tileBottom = NSColor(hex: 0x111214)

    /// The glyph's own size in points; everything else scales it.
    static let glyphSize = CGSize(width: 20, height: 18)

    /// Draws the glyph in `color`, scaled from its 20×18 design, origin bottom-left at `origin`:
    /// a bear peeking over a sesame bun with a bug sitting on it.
    /// A filled dot means recording, a ring means the buffer is running.
    static func drawGlyph(in context: CGContext, origin: CGPoint, scale: CGFloat, color: NSColor, recording: Bool = false, buffering: Bool = false) {
        context.saveGState()
        // The shapes below use a top-left origin, like the SVG mockups they came from.
        context.translateBy(x: origin.x, y: origin.y + glyphSize.height * scale)
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -0.6, y: -1.0)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(color.cgColor)
        context.setStrokeColor(color.cgColor)
        context.setLineCap(.round)

        // Bear: ears, head, eyes, nose.
        ellipse(context, 4.8, 4, 2.6, 2.6, .shape)
        ellipse(context, 15.2, 4, 2.6, 2.6, .shape)
        ellipse(context, 10, 8, 6.8, 5.9, .shape)
        ellipse(context, 7.55, 6.8, 0.95, 0.95, .hole)
        ellipse(context, 12.45, 6.8, 0.95, 0.95, .hole)
        ellipse(context, 10, 9.2, 1.1, 0.75, .hole)

        // The bun in front, with a gap around it and sesame seeds.
        ellipse(context, 10, 14.1, 8.9, 4.3, .hole)
        ellipse(context, 10, 14.1, 8, 3.45, .shape)
        let seeds: [(x: CGFloat, y: CGFloat, angle: CGFloat)] = [(6.2, 13, -20), (8.6, 12.2, 5), (7.4, 14.9, 30), (10.2, 14.6, -10), (11.2, 12.5, 20)]
        for seed in seeds {
            ellipse(context, seed.x, seed.y, 0.42, 0.25, .hole, angle: seed.angle)
        }

        drawBug(in: context)

        if recording || buffering {
            ellipse(context, 19.3, 2.6, 2.9, 2.9, .hole)
            if recording {
                ellipse(context, 19.3, 2.6, 2.1, 2.1, .shape)
            } else {
                context.setBlendMode(.normal)
                context.setLineWidth(1.1)
                context.strokeEllipse(in: CGRect(x: 19.3 - 1.5, y: 2.6 - 1.5, width: 3, height: 3))
            }
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// The bug on the bun: shell with a seam and spots, head, antennae and six legs.
    private static func drawBug(in context: CGContext) {
        context.saveGState()
        context.translateBy(x: 15.6, y: 11.4)
        context.rotate(by: 28 * .pi / 180)
        context.scaleBy(x: 0.72, y: 0.72)

        var legs: [(from: CGPoint, to: CGPoint)] = []
        for side in [CGFloat(-1), CGFloat(1)] {
            legs.append((from: CGPoint(x: side * 1.6, y: -0.4), to: CGPoint(x: side * 3.0, y: -1.3)))
            legs.append((from: CGPoint(x: side * 1.9, y: 0.8), to: CGPoint(x: side * 3.3, y: 0.8)))
            legs.append((from: CGPoint(x: side * 1.6, y: 2.0), to: CGPoint(x: side * 2.9, y: 3.1)))
        }
        // Each leg and antenna is cut out wide first, then drawn thin inside the cut.
        strokeLegs(context, legs, width: 1.6, .hole)
        strokeAntennae(context, width: 1.5, .hole)
        ellipse(context, 0, 0.6, 2.75, 3.15, .hole)
        ellipse(context, 0, -2.6, 1.7, 1.7, .hole)
        strokeLegs(context, legs, width: 0.55, .shape)
        strokeAntennae(context, width: 0.5, .shape)
        ellipse(context, 0, 0.6, 2, 2.4, .shape)
        ellipse(context, 0, -2.6, 1.05, 1.05, .shape)

        context.setBlendMode(.clear)
        context.setLineWidth(0.4)
        context.strokeLineSegments(between: [CGPoint(x: 0, y: -1.6), CGPoint(x: 0, y: 3.0)])
        ellipse(context, -0.9, 0.1, 0.38, 0.38, .hole)
        ellipse(context, 0.9, 1.3, 0.38, 0.38, .hole)
        ellipse(context, -0.8, 1.9, 0.38, 0.38, .hole)
        ellipse(context, 0.85, -0.3, 0.38, 0.38, .hole)
        context.setBlendMode(.normal)
        context.restoreGState()
    }

    /// `shape` paints the glyph, `hole` cuts through everything painted so far.
    private enum Ink {
        case shape
        case hole
    }

    private static func use(_ ink: Ink, in context: CGContext) {
        if ink == .shape {
            context.setBlendMode(.normal)
        } else {
            context.setBlendMode(.clear)
        }
    }

    private static func ellipse(_ context: CGContext, _ centerX: CGFloat, _ centerY: CGFloat, _ radiusX: CGFloat, _ radiusY: CGFloat, _ ink: Ink, angle: CGFloat = 0) {
        use(ink, in: context)
        context.saveGState()
        context.translateBy(x: centerX, y: centerY)
        context.rotate(by: angle * .pi / 180)
        context.fillEllipse(in: CGRect(x: -radiusX, y: -radiusY, width: radiusX * 2, height: radiusY * 2))
        context.restoreGState()
    }

    private static func strokeLegs(_ context: CGContext, _ legs: [(from: CGPoint, to: CGPoint)], width: CGFloat, _ ink: Ink) {
        use(ink, in: context)
        context.setLineWidth(width)
        for leg in legs {
            context.strokeLineSegments(between: [leg.from, leg.to])
        }
    }

    private static func strokeAntennae(_ context: CGContext, width: CGFloat, _ ink: Ink) {
        use(ink, in: context)
        context.setLineWidth(width)
        for side in [CGFloat(-1), CGFloat(1)] {
            context.beginPath()
            context.move(to: CGPoint(x: side * 0.5, y: -3.4))
            context.addQuadCurve(to: CGPoint(x: side * 1.9, y: -4.7), control: CGPoint(x: side * 1.0, y: -4.4))
            context.strokePath()
        }
    }

    /// Draws the app icon into a context with origin bottom-left, `size` points square:
    /// the white glyph on a dark squircle.
    static func drawIcon(in context: CGContext, size: CGFloat) {
        context.saveGState()
        let unit = size / 1024

        let inset = 100 * unit
        let backgroundRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let radius = backgroundRect.width * 0.225
        let background = CGPath(roundedRect: backgroundRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 24 * unit, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        context.addPath(background)
        context.setFillColor(tileBottom.cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(background)
        context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [tileTop.cgColor, tileBottom.cgColor] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: backgroundRect.maxY), end: CGPoint(x: 0, y: backgroundRect.minY), options: [])
        context.restoreGState()

        // The glyph fills about 60% of the tile, centered.
        let scale = backgroundRect.width * 0.6 / glyphSize.width
        let glyphWidth = glyphSize.width * scale
        let glyphHeight = glyphSize.height * scale
        let origin = CGPoint(x: backgroundRect.midX - glyphWidth / 2, y: backgroundRect.midY - glyphHeight / 2)
        drawGlyph(in: context, origin: origin, scale: scale, color: NSColor(hex: 0xF4F4F5))
        context.restoreGState()
    }

    /// PNG-ready bitmap of the icon at a pixel size.
    static func iconImage(pixels: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        drawIcon(in: context, size: CGFloat(pixels))
        return context.makeImage()
    }

    static var nsImage: NSImage {
        let image = NSImage(size: NSSize(width: 256, height: 256))
        if let cgImage = iconImage(pixels: 512) {
            image.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
        }
        return image
    }

    /// Monochrome template glyph for the menu bar and the in-app logo.
    static func menuBarImage(recording: Bool, buffering: Bool = false) -> NSImage {
        let image = NSImage(size: glyphSize, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            drawGlyph(in: context, origin: .zero, scale: 1, color: .black, recording: recording, buffering: buffering)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Writes an .iconset folder (all sizes macOS needs) for `iconutil`.
    static func writeIconset(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let sizes: [(name: String, pixels: Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for entry in sizes {
            guard let image = iconImage(pixels: entry.pixels) else { continue }
            let url = folder.appendingPathComponent(entry.name + ".png")
            ImageFiles.write(image, to: url, type: "public.png")
        }
    }
}

/// The bear glyph in the current text color, the same picture as in the menu bar.
struct LogoView: View {
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: Logo.menuBarImage(recording: false))
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityLabel("Bugbear logo")
    }
}
