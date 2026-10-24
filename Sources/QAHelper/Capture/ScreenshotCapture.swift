import AppKit

enum ScreenshotMode {
    case area
    case window
    case fullScreen
    case allDisplays
}

/// Uses the system `screencapture` tool so area and window selection look native.
enum ScreenshotCapture {
    /// Returns the PNG file, or nil when the user pressed Esc.
    static func capture(_ mode: ScreenshotMode) async -> URL? {
        let url = AppPaths.temporary.appendingPathComponent("shot-\(UUID().uuidString).png")
        switch mode {
        case .area:
            // -i interactive, -s selection only; Space inside switches to window mode.
            _ = await run(["-x", "-i", "-s", url.path])
        case .window:
            // -o: no window shadow.
            _ = await run(["-x", "-i", "-w", "-o", url.path])
        case .fullScreen:
            _ = await run(["-x", "-m", url.path])
        case .allDisplays:
            return await captureAllDisplays(into: url)
        }
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    private static func run(_ arguments: [String]) async -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            return -1
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                continuation.resume()
            }
        }
        return process.terminationStatus
    }

    /// One file per display from `screencapture`, then stitched left to right in screen order.
    private static func captureAllDisplays(into url: URL) async -> URL? {
        let screens = await MainActor.run { NSScreen.screens.map { screen in screen.frame } }
        var parts: [URL] = []
        for index in 0..<screens.count {
            parts.append(AppPaths.temporary.appendingPathComponent("display-\(index)-\(UUID().uuidString).png"))
        }
        _ = await run(["-x"] + parts.map { part in part.path })
        defer {
            for part in parts {
                try? FileManager.default.removeItem(at: part)
            }
        }
        // screencapture writes displays in NSScreen order.
        var images: [(image: CGImage, frame: CGRect)] = []
        for (index, part) in parts.enumerated() {
            if let image = ImageFiles.load(part) {
                images.append((image: image, frame: screens[index]))
            }
        }
        if images.isEmpty { return nil }
        if images.count == 1 {
            ImageFiles.write(images[0].image, to: url, type: "public.png")
            return url
        }
        images.sort { first, second in first.frame.minX < second.frame.minX }
        guard let stitched = stitchHorizontally(images.map { item in item.image }) else { return nil }
        ImageFiles.write(stitched, to: url, type: "public.png")
        return url
    }

    /// Places images left to right, scaled to the tallest one's height, with a small gap.
    static func stitchHorizontally(_ images: [CGImage], gap: Int = 0) -> CGImage? {
        guard let tallest = images.map({ image in image.height }).max() else { return nil }
        var widths: [Int] = []
        for image in images {
            let scale = Double(tallest) / Double(image.height)
            widths.append(Int(Double(image.width) * scale))
        }
        var totalWidth = gap * max(0, images.count - 1)
        for width in widths {
            totalWidth += width
        }
        guard let context = CGContext(data: nil, width: totalWidth, height: tallest, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(NSColor(hex: 0x131416).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: totalWidth, height: tallest))
        context.interpolationQuality = .high
        var x = 0
        for (index, image) in images.enumerated() {
            context.draw(image, in: CGRect(x: x, y: 0, width: widths[index], height: tallest))
            x += widths[index] + gap
        }
        return context.makeImage()
    }
}
