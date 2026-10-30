// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AppKit
import AppCore
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// `--whats-new-media <folder>`: animated pictures for "What's new", drawn off screen from the same
/// code the app uses, so they show the real thing.
@MainActor
enum WhatsNewMedia {
    static let size = CGSize(width: 640, height: 400)
    static let framesPerSecond = 8.0
    static let seconds = 7.5

    /// A sign-in page: click Email, type, click Sign in, the account page opens, click Orders.
    /// The caption at the bottom is the step the video editor shows with "Show steps".
    static func writeStepsGIF(to url: URL) -> Bool {
        let events = stepEvents()
        let layers = VideoCompositor.Layers()
        layers.renderSize = size
        layers.steps = VideoCompositor.stepCaptions(events: events, timeMap: nil, renderSize: size, unit: 0.8)
        let timeMap = TimeMap(pieces: EditTimeline(sourceDuration: seconds).pieces())
        let context = CIContext()

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, Int(seconds * framesPerSecond), nil) else { return false }
        let fileProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary
        CGImageDestinationSetProperties(destination, fileProperties)
        let frameProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1 / framesPerSecond]] as CFDictionary
        var frame = 0
        while Double(frame) / framesPerSecond < seconds {
            let time = Double(frame) / framesPerSecond
            guard let page = drawPage(at: time) else { return false }
            let composed = VideoCompositor.renderFrame(source: CIImage(cgImage: page), outputTime: time, timeMap: timeMap, layers: layers)
            guard let image = context.createCGImage(composed, from: CGRect(origin: .zero, size: size)) else { return false }
            CGImageDestinationAddImage(destination, image, frameProperties)
            frame += 1
        }
        return CGImageDestinationFinalize(destination)
    }

    private static let typed = "john@test.com"
    private static let typingStart = 1.2
    private static let typingEnd = 2.6

    private static func stepEvents() -> [InputEvent] {
        var events: [InputEvent] = []
        events.append(InputEvent(kind: .click, time: 0.6, x: 0, y: 0, label: "", target: "\"Email\" text field", app: "Chrome", url: "https://shop.test/login"))
        var typing = InputEvent(kind: .key, time: typingStart, x: 0, y: 0, label: InputEventRecorder.typingLabel, target: "\"Email\" text field", app: "Chrome", url: "https://shop.test/login")
        typing.text = typed
        events.append(typing)
        events.append(InputEvent(kind: .click, time: 3.6, x: 0, y: 0, label: "", target: "\"Sign in\" button", app: "Chrome", url: "https://shop.test/login"))
        events.append(InputEvent(kind: .click, time: 5.4, x: 0, y: 0, label: "", target: "\"Orders\" link", app: "Chrome", url: "https://shop.test/account"))
        return events
    }

    // MARK: Drawing (origin bottom-left, like Core Image)

    private static func drawPage(at time: Double) -> CGImage? {
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.current = previous }

        NSColor(hex: 0xF4F5F7).setFill()
        CGRect(origin: .zero, size: size).fill()
        let isAccountPage = time >= 4.4
        drawBrowserBar(address: isAccountPage ? "shop.test/account" : "shop.test/login")
        if isAccountPage {
            drawAccountPage()
        } else {
            drawLoginPage(at: time)
        }
        drawPointer(at: pointer(at: time), pressed: isPressed(at: time))
        return context.makeImage()
    }

    private static func drawBrowserBar(address: String) {
        NSColor(hex: 0xE3E5E8).setFill()
        CGRect(x: 0, y: size.height - 44, width: size.width, height: 44).fill()
        for (index, color) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            NSColor(hex: UInt32(color)).setFill()
            NSBezierPath(ovalIn: CGRect(x: 16 + CGFloat(index) * 18, y: size.height - 28, width: 11, height: 11)).fill()
        }
        NSColor.white.setFill()
        NSBezierPath(roundedRect: CGRect(x: 90, y: size.height - 34, width: size.width - 120, height: 24), xRadius: 6, yRadius: 6).fill()
        text(address, at: CGPoint(x: 104, y: size.height - 29), size: 13, color: NSColor(hex: 0x3C3F44))
    }

    private static let emailField = CGRect(x: 170, y: 220, width: 300, height: 36)
    private static let signInButton = CGRect(x: 170, y: 160, width: 300, height: 38)
    private static let ordersLink = CGPoint(x: 190, y: 228)

    private static func drawLoginPage(at time: Double) {
        text("Sign in to Shop", at: CGPoint(x: 170, y: 290), size: 22, color: NSColor(hex: 0x1C1D20), weight: .bold)
        text("Email", at: CGPoint(x: 170, y: 262), size: 12, color: NSColor(hex: 0x5B5F66))
        NSColor.white.setFill()
        let field = NSBezierPath(roundedRect: emailField, xRadius: 6, yRadius: 6)
        field.fill()
        let focused = time >= 0.6
        (focused ? NSColor(hex: 0x4C9BFF) : NSColor(hex: 0xC9CCD1)).setStroke()
        field.lineWidth = focused ? 2 : 1
        field.stroke()
        var count = 0
        if time >= typingStart {
            count = min(typed.count, Int((time - typingStart) / (typingEnd - typingStart) * Double(typed.count)) + 1)
        }
        text(String(typed.prefix(count)), at: CGPoint(x: emailField.minX + 12, y: emailField.minY + 10), size: 14, color: NSColor(hex: 0x1C1D20))
        NSColor(hex: 0xFF6B4A).setFill()
        NSBezierPath(roundedRect: signInButton, xRadius: 6, yRadius: 6).fill()
        text("Sign in", at: CGPoint(x: signInButton.midX - 24, y: signInButton.minY + 11), size: 14, color: .white, weight: .semibold)
    }

    private static func drawAccountPage() {
        text("Hello, John", at: CGPoint(x: 170, y: 290), size: 22, color: NSColor(hex: 0x1C1D20), weight: .bold)
        text("Orders", at: CGPoint(x: 170, y: 220), size: 15, color: NSColor(hex: 0x2F6FDB), weight: .semibold)
        text("Addresses", at: CGPoint(x: 170, y: 190), size: 15, color: NSColor(hex: 0x2F6FDB), weight: .semibold)
    }

    /// Where the pointer is: it glides between the things it clicks.
    private static func pointer(at time: Double) -> CGPoint {
        let path: [(time: Double, point: CGPoint)] = [
            (time: 0, point: CGPoint(x: 520, y: 120)),
            (time: 0.6, point: CGPoint(x: emailField.minX + 60, y: emailField.midY)),
            (time: 3.0, point: CGPoint(x: emailField.minX + 60, y: emailField.midY)),
            (time: 3.6, point: CGPoint(x: signInButton.midX, y: signInButton.midY)),
            (time: 4.6, point: CGPoint(x: signInButton.midX, y: signInButton.midY)),
            (time: 5.4, point: ordersLink),
            (time: seconds, point: ordersLink),
        ]
        for index in 1..<path.count where time <= path[index].time {
            let from = path[index - 1]
            let to = path[index]
            let progress = max(0, min(1, (time - from.time) / max(0.01, to.time - from.time)))
            let eased = progress * progress * (3 - 2 * progress)
            return CGPoint(x: from.point.x + (to.point.x - from.point.x) * eased, y: from.point.y + (to.point.y - from.point.y) * eased)
        }
        return ordersLink
    }

    private static func isPressed(at time: Double) -> Bool {
        for click in [0.6, 3.6, 5.4] where time >= click && time < click + 0.25 {
            return true
        }
        return false
    }

    private static func drawPointer(at tip: CGPoint, pressed: Bool) {
        if pressed {
            NSColor(hex: 0xFF6B4A, alpha: 0.35).setFill()
            NSBezierPath(ovalIn: CGRect(x: tip.x - 18, y: tip.y - 18, width: 36, height: 36)).fill()
        }
        let arrow = NSBezierPath()
        arrow.move(to: tip)
        arrow.line(to: CGPoint(x: tip.x, y: tip.y - 20))
        arrow.line(to: CGPoint(x: tip.x + 5, y: tip.y - 15))
        arrow.line(to: CGPoint(x: tip.x + 9, y: tip.y - 23))
        arrow.line(to: CGPoint(x: tip.x + 12, y: tip.y - 21))
        arrow.line(to: CGPoint(x: tip.x + 8, y: tip.y - 14))
        arrow.line(to: CGPoint(x: tip.x + 14, y: tip.y - 14))
        arrow.close()
        NSColor.black.setFill()
        arrow.fill()
        NSColor.white.setStroke()
        arrow.lineWidth = 1.2
        arrow.stroke()
    }

    private static func text(_ value: String, at point: CGPoint, size fontSize: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: weight), .foregroundColor: color]
        (value as NSString).draw(at: point, withAttributes: attributes)
    }
}
#endif
