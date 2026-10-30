import CoreGraphics
import Foundation

/// The pure part of the scrolling screenshot: row signatures of a frame, the sticky footer, and
/// gluing the frames into one long image. Capturing and scrolling stay in the app.
public enum ScrollStitching {
    public static func rowSignatures(_ image: CGImage) -> [[UInt8]?] {
        let width = image.width
        let height = image.height
        guard let pixels = rgba(image, width: width, height: height) else { return [] }
        var rows: [[UInt8]?] = []
        pixels.withUnsafeBufferPointer { buffer in
            for row in 0..<height {
                rows.append(ScrollStitcher.rowSignature(buffer, rowStart: row * width * 4, width: width))
            }
        }
        return rows
    }

    /// Rows at the bottom that did not change between the first two frames: a sticky footer or toolbar.
    /// Compared pixel by pixel, so the footer's plain-colored part counts too.
    public static func stickyFooterRows(_ frames: [CGImage]) -> Int {
        if frames.count < 2 { return 0 }
        let first = frames[0]
        let second = frames[1]
        let width = first.width
        let height = first.height
        guard second.width == width, second.height == height,
              let upper = rgba(first, width: width, height: height),
              let lower = rgba(second, width: width, height: height) else { return 0 }
        var count = 0
        var row = height - 1
        while row >= 0 {
            var total = 0
            let start = row * width * 4
            var index = start
            while index < start + width * 4 {
                total += abs(Int(upper[index]) - Int(lower[index]))
                index += 4
            }
            // Average difference under 2 levels on the red channel: the row did not move.
            if total > width * 2 { break }
            count += 1
            row -= 1
        }
        // Never call most of the area a footer.
        if count > height / 3 { return 0 }
        // The footer's soft top edge or shadow changes a little between frames: take a few rows more.
        // Slices stay continuous whatever the footer height, so this costs no content.
        if count > 0 {
            count = min(height / 3, count + 4)
        }
        return count
    }

    /// First frame without its footer, then from every next frame only the newly scrolled-in rows,
    /// then the footer once at the end.
    public static func stitch(frames: [CGImage], shifts: [Int], signatures: [[[UInt8]?]]) -> CGImage? {
        guard let first = frames.first else { return nil }
        let width = first.width
        let frameHeight = first.height
        let footer = stickyFooterRows(frames)
        var height = frameHeight
        for shift in shifts {
            height += shift
        }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Core Graphics counts from the bottom; `top` counts from the top of the long image.
        var top = 0
        let firstBody = frameHeight - footer
        if let part = first.cropping(to: CGRect(x: 0, y: 0, width: width, height: firstBody)) {
            context.draw(part, in: CGRect(x: 0, y: height - top - firstBody, width: width, height: firstBody))
        }
        top += firstBody
        for (index, shift) in shifts.enumerated() {
            let frame = frames[index + 1]
            let sliceTop = frameHeight - footer - shift
            if sliceTop < 0 || shift <= 0 { continue }
            if let part = frame.cropping(to: CGRect(x: 0, y: sliceTop, width: width, height: shift)) {
                context.draw(part, in: CGRect(x: 0, y: height - top - shift, width: width, height: shift))
            }
            top += shift
        }
        if footer > 0, let last = frames.last, let part = last.cropping(to: CGRect(x: 0, y: frameHeight - footer, width: width, height: footer)) {
            context.draw(part, in: CGRect(x: 0, y: height - top - footer, width: width, height: footer))
        }
        return context.makeImage()
    }

    /// Pixels of `image` as RGBA bytes, drawn at the given size.
    static func rgba(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        if !drawn { return nil }
        return pixels
    }
}
