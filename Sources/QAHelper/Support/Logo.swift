import AppKit
import SwiftUI

/// The QA Helper logo: a bear happily eating a bun, in black and white.
/// Drawn in code so the app icon, menu bar glyph and in-app logo share one source.
enum Logo {
    // Black and white: a light bear on a near-black squircle, matching the menu bar glyph.
    static let purpleTop = NSColor(hex: 0x3A3C41)
    static let purpleBottom = NSColor(hex: 0x111214)
    static let fur = NSColor(hex: 0xECEDEE)
    static let furDark = NSColor(hex: 0xBFC1C6)
    static let muzzle = NSColor(hex: 0xFFFFFF)
    static let innerEar = NSColor(hex: 0x9EA1A8)
    static let nose = NSColor(hex: 0x141416)
    static let cheek = NSColor(hex: 0x8E9198, alpha: 0.45)
    static let bunTop = NSColor(hex: 0x6E7178)
    static let bunBottom = NSColor(hex: 0x3F4147)
    static let sesame = NSColor(hex: 0xF4F4F5)

    /// Draws the full-color icon into a context with origin bottom-left, `size` points square.
    static func drawIcon(in context: CGContext, size: CGFloat) {
        context.saveGState()
        let unit = size / 1024

        // Squircle background with a vertical purple gradient.
        let inset = 100 * unit
        let backgroundRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let radius = backgroundRect.width * 0.225
        let background = CGPath(roundedRect: backgroundRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 24 * unit, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        context.addPath(background)
        context.setFillColor(purpleBottom.cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(background)
        context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [purpleTop.cgColor, purpleBottom.cgColor] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: backgroundRect.maxY), end: CGPoint(x: 0, y: backgroundRect.minY), options: [])
        // Soft light spot behind the bear.
        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(glow, startCenter: CGPoint(x: 512 * unit, y: 560 * unit), startRadius: 0, endCenter: CGPoint(x: 512 * unit, y: 560 * unit), endRadius: 360 * unit, options: [])
        context.restoreGState()

        drawBear(in: context, unit: unit)
        context.restoreGState()
    }

    private static func circle(_ context: CGContext, _ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ color: NSColor) {
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }

    private static func ellipse(_ context: CGContext, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: NSColor) {
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height))
    }

    private static func drawBear(in context: CGContext, unit: CGFloat) {
        func point(_ value: CGFloat) -> CGFloat { value * unit }

        // Ears.
        circle(context, point(330), point(735), point(92), fur)
        circle(context, point(694), point(735), point(92), fur)
        circle(context, point(330), point(735), point(52), innerEar)
        circle(context, point(694), point(735), point(52), innerEar)

        // Head.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -6 * unit), blur: 18 * unit, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        ellipse(context, point(512), point(560), point(470), point(430), fur)
        context.restoreGState()

        // Muzzle.
        ellipse(context, point(512), point(478), point(250), point(190), muzzle)

        // Happy closed eyes (eating): small upward arcs.
        context.setStrokeColor(nose.cgColor)
        context.setLineWidth(point(16))
        context.setLineCap(.round)
        for centerX in [CGFloat(418), CGFloat(606)] {
            context.beginPath()
            context.addArc(center: CGPoint(x: point(centerX), y: point(600)), radius: point(34), startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: false)
            context.strokePath()
        }

        // Cheeks.
        ellipse(context, point(372), point(520), point(70), point(44), cheek)
        ellipse(context, point(652), point(520), point(70), point(44), cheek)

        // Nose.
        ellipse(context, point(512), point(530), point(74), point(52), nose)
        ellipse(context, point(498), point(540), point(22), point(12), NSColor.white.withAlphaComponent(0.35))

        // Bun held in front of the mouth, with a bite taken out of the top-right.
        drawBun(in: context, unit: unit)

        // Paws holding the bun.
        circle(context, point(352), point(352), point(62), furDark)
        circle(context, point(672), point(352), point(62), furDark)
        circle(context, point(352), point(352), point(44), fur)
        circle(context, point(672), point(352), point(44), fur)
    }

    private static func drawBun(in context: CGContext, unit: CGFloat) {
        func point(_ value: CGFloat) -> CGFloat { value * unit }
        let bunRect = CGRect(x: point(345), y: point(268), width: point(334), height: point(190))
        let bites: [(x: CGFloat, y: CGFloat)] = [(x: 612, y: 462), (x: 662, y: 438), (x: 690, y: 396)]
        let biteRadius = point(38)

        // Shadow under the bun, drawn outside the layer so the bite does not cut it.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -6 * unit), blur: 14 * unit, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        context.setFillColor(bunBottom.withAlphaComponent(0.01).cgColor)
        context.fillEllipse(in: bunRect.insetBy(dx: point(20), dy: point(10)))
        context.restoreGState()

        // Bun in its own transparency layer so the bite can be erased cleanly.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.saveGState()
        context.addEllipse(in: bunRect)
        context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [bunTop.cgColor, bunBottom.cgColor] as CFArray, locations: [0.2, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: bunRect.maxY), end: CGPoint(x: 0, y: bunRect.minY), options: [])

        // Sesame seeds.
        let seeds: [(x: CGFloat, y: CGFloat, angle: CGFloat)] = [(430, 410, 20), (480, 432, -15), (530, 418, 30), (465, 384, -35), (560, 392, 10), (405, 372, 25)]
        for seed in seeds {
            context.saveGState()
            context.translateBy(x: point(seed.x), y: point(seed.y))
            context.rotate(by: seed.angle * .pi / 180)
            context.setFillColor(sesame.cgColor)
            context.fillEllipse(in: CGRect(x: -point(11), y: -point(6), width: point(22), height: point(12)))
            context.restoreGState()
        }

        // Light crumb rim around the bite: a slightly bigger circle in crumb color...
        context.setFillColor(NSColor(hex: 0xA9ACB2).cgColor)
        for bite in bites {
            let radius = biteRadius + point(9)
            context.fillEllipse(in: CGRect(x: point(bite.x) - radius, y: point(bite.y) - radius, width: radius * 2, height: radius * 2))
        }
        context.restoreGState()

        // ...then erase the bite itself.
        context.setBlendMode(.clear)
        for bite in bites {
            context.fillEllipse(in: CGRect(x: point(bite.x) - biteRadius, y: point(bite.y) - biteRadius, width: biteRadius * 2, height: biteRadius * 2))
        }
        context.setBlendMode(.normal)
        context.endTransparencyLayer()
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

    /// Monochrome template glyph for the menu bar: bear head with a bun.
    /// A filled dot means recording, a ring means the buffer is running.
    static func menuBarImage(recording: Bool, buffering: Bool = false) -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
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

struct LogoView: View {
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: Logo.nsImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityLabel("QA Helper logo")
    }
}
