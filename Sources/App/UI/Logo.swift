import AppKit
import SwiftUI
import AppCore

/// The app's logo: a bear looking through a magnifying glass at a bug, as one flat shape.
/// Drawn in code so the menu bar glyph, the in-app logo and the app icon are the same picture.
enum Logo {
    static let tileTop = NSColor(hex: 0x3A3C41)
    static let tileBottom = NSColor(hex: 0x111214)

    /// The glyph's own size in points; everything else scales it.
    static let glyphSize = CGSize(width: 20, height: 19)

    /// Draws the glyph in `color`, scaled from its 20×19 design, origin bottom-left at `origin`:
    /// a bear in the top left looks down through a magnifying glass at a bug.
    /// A filled dot means recording, a ring means the buffer is running.
    static func drawGlyph(in context: CGContext, origin: CGPoint, scale: CGFloat, color: NSColor, recording: Bool = false, buffering: Bool = false) {
        context.saveGState()
        // The shapes below use a top-left origin, like the SVG mockups they came from.
        context.translateBy(x: origin.x, y: origin.y + glyphSize.height * scale)
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -0.6, y: -0.4)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(color.cgColor)
        context.setStrokeColor(color.cgColor)
        context.setLineCap(.round)

        drawBear(in: context)

        // The magnifying glass: the handle cut wide and drawn inside the cut, then a gap around
        // the lens, the ring, and clear glass.
        let handle = [CGPoint(x: 16.4, y: 15.1), CGPoint(x: 19.3, y: 17.8)]
        use(.hole, in: context)
        context.setLineWidth(3.4)
        context.strokeLineSegments(between: handle)
        use(.shape, in: context)
        context.setLineWidth(2)
        context.strokeLineSegments(between: handle)
        ellipse(context, 13.1, 11.6, 5.45, 5.45, .hole)
        ellipse(context, 13.1, 11.6, 4.7, 4.7, .shape)
        ellipse(context, 13.1, 11.6, 3.85, 3.85, .hole)

        drawBug(in: context)

        if recording || buffering {
            ellipse(context, 17.6, 2.8, 2.9, 2.9, .hole)
            if recording {
                ellipse(context, 17.6, 2.8, 2.1, 2.1, .shape)
            } else {
                context.setBlendMode(.normal)
                context.setLineWidth(1.1)
                context.strokeEllipse(in: CGRect(x: 17.6 - 1.5, y: 2.8 - 1.5, width: 3, height: 3))
            }
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// The bear in the top left: ears, head, and eyes looking down at the glass, nose.
    private static func drawBear(in context: CGContext) {
        context.saveGState()
        context.translateBy(x: -0.6, y: -0.5)
        context.scaleBy(x: 0.78, y: 0.78)
        ellipse(context, 4.8, 4, 2.6, 2.6, .shape)
        ellipse(context, 15.2, 4, 2.6, 2.6, .shape)
        ellipse(context, 10, 8, 6.8, 5.9, .shape)
        ellipse(context, 8.05, 7.2, 0.95, 0.95, .hole)
        ellipse(context, 12.95, 7.2, 0.95, 0.95, .hole)
        ellipse(context, 10, 9.2, 1.1, 0.75, .hole)
        context.restoreGState()
    }

    /// The bug in the glass: shell with a seam and two spots, head and antennae.
    private static func drawBug(in context: CGContext) {
        context.saveGState()
        context.translateBy(x: 13.1, y: 11.9)
        context.rotate(by: 20 * .pi / 180)
        context.scaleBy(x: 0.82, y: 0.82)

        let antennae = [
            CGPoint(x: -0.5, y: -2.7), CGPoint(x: -1.3, y: -3.7),
            CGPoint(x: 0.5, y: -2.7), CGPoint(x: 1.3, y: -3.7),
        ]
        // The antennae are cut out wide first, then drawn thin inside the cut.
        use(.hole, in: context)
        context.setLineWidth(1.5)
        context.strokeLineSegments(between: antennae)
        ellipse(context, 0, 0.5, 2.6, 2.8, .hole)
        ellipse(context, 0, -1.9, 1.6, 1.6, .hole)
        use(.shape, in: context)
        context.setLineWidth(0.6)
        context.strokeLineSegments(between: antennae)
        ellipse(context, 0, 0.5, 1.9, 2.1, .shape)
        ellipse(context, 0, -1.9, 0.95, 0.95, .shape)

        use(.hole, in: context)
        context.setLineWidth(0.5)
        context.strokeLineSegments(between: [CGPoint(x: 0, y: -1.2), CGPoint(x: 0, y: 2.6)])
        ellipse(context, -0.9, 0.2, 0.45, 0.45, .hole)
        ellipse(context, 0.9, 1.3, 0.45, 0.45, .hole)
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
            .accessibilityLabel(L("ui.logo.accessibility", AppInfo.name))
    }
}
