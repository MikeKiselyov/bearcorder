import AppKit
import SwiftUI

/// The QA Helper logo: a bear head eating a bun, as one flat shape.
/// Drawn in code so the menu bar glyph, the in-app logo and the app icon are the same picture.
enum Logo {
    static let tileTop = NSColor(hex: 0x3A3C41)
    static let tileBottom = NSColor(hex: 0x111214)

    /// The glyph's own size in points; everything else scales it.
    static let glyphSize = CGSize(width: 20, height: 18)

    /// Draws the bear glyph in `color`, scaled from its 20×18 design, origin bottom-left at `origin`.
    /// A filled dot means recording, a ring means the buffer is running.
    static func drawGlyph(in context: CGContext, origin: CGPoint, scale: CGFloat, color: NSColor, recording: Bool = false, buffering: Bool = false) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: scale, y: scale)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(color.cgColor)
        context.setStrokeColor(color.cgColor)
        // Ears and head.
        context.fillEllipse(in: CGRect(x: 2.2, y: 10.5, width: 5.2, height: 5.2))
        context.fillEllipse(in: CGRect(x: 12.6, y: 10.5, width: 5.2, height: 5.2))
        context.fillEllipse(in: CGRect(x: 3.2, y: 3, width: 13.6, height: 12.2))
        // Punch out the eyes and a bun shape so the face reads at 18 px.
        context.setBlendMode(.clear)
        context.fillEllipse(in: CGRect(x: 6.6, y: 9.6, width: 1.9, height: 1.9))
        context.fillEllipse(in: CGRect(x: 11.5, y: 9.6, width: 1.9, height: 1.9))
        context.fillEllipse(in: CGRect(x: 5.4, y: 2.2, width: 9.2, height: 5.0))
        context.setBlendMode(.normal)
        context.fillEllipse(in: CGRect(x: 6.6, y: 3.1, width: 6.8, height: 3.2))
        if recording {
            context.fillEllipse(in: CGRect(x: 15.5, y: 0, width: 4.5, height: 4.5))
        } else if buffering {
            context.setLineWidth(1.2)
            context.strokeEllipse(in: CGRect(x: 16.1, y: 0.6, width: 3.3, height: 3.3))
        }
        context.endTransparencyLayer()
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
            .accessibilityLabel("QA Helper logo")
    }
}
