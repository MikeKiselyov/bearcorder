// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AppKit
import AVFoundation
import BugbearCore
import SwiftUI

/// `--readme-media <folder>`: the pictures and GIF frames for README.md. Everything is rendered off screen
/// from a demo library inside the folder (a made-up checkout page), so real captures never show up and no
/// permissions are needed. `scripts/dev/readme-media.sh` turns the output into `docs/images`.
@MainActor
enum ReadmeMedia {
    static func make(folder: URL) async -> Int32 {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        AppPaths.supportOverride = folder.appendingPathComponent("library", isDirectory: true)

        let screens = folder.appendingPathComponent("screens", isDirectory: true)
        guard let shot = addDemoScreenshot(), let clip = await addDemoClip() else {
            print("Could not make the demo captures")
            return 1
        }

        // Menu tabs, toolbox, settings, history, onboarding, area picker: the regular snapshot set.
        let status = await DevChecks.snapshot(folder: screens)
        if status != 0 {
            return status
        }
        Updater.shared.state = .idle
        for tab in MenuTab.allCases {
            UserDefaults.standard.set(tab.rawValue, forKey: "menuTab")
            DevChecks.render(MenuBarView().environment(AppState.shared), size: CGSize(width: 360, height: 719), to: screens.appendingPathComponent("menu-\(tab.rawValue.lowercased()).png"))
        }

        if let icon = Logo.iconImage(pixels: 256) {
            ImageFiles.write(icon, to: screens.appendingPathComponent("logo.png"), type: "public.png")
        }
        let videoEditor = screens.appendingPathComponent("video-editor.png")
        render(VideoEditorView(capture: clip).environment(AppState.shared), size: CGSize(width: 1220, height: 800), wait: 3, to: videoEditor)
        if let frame = clipPreviewFrame() {
            fillPlayer(in: videoEditor, with: frame)
        }
        // Picking the part of the clip to keep: the whole frame, the crop with its handles and size.
        if let frame = clipPreviewFrame() {
            let size = CGSize(width: 960, height: 600)
            let crop = CGRect(x: 0.08, y: 0.12, width: 0.62, height: 0.5)
            let picture = ZStack(alignment: .topLeading) {
                Image(nsImage: NSImage(cgImage: frame, size: size))
                    .resizable()
                    .frame(width: size.width, height: size.height)
                VideoCropOverlay(crop: crop, videoRect: CGRect(origin: .zero, size: size), sourceSize: CGSize(width: frame.width, height: frame.height))
                VideoCropBar(hasCrop: true, onReset: {}, onDone: {})
            }
            .preferredColorScheme(.dark)
            DevChecks.render(picture, size: size, to: screens.appendingPathComponent("video-crop.png"))
        }
        // A clip from two displays in the narrowest editor window: the screen picker must not push
        // the side panel out of the window (it did, "Copy" and the switches were cut off).
        var twoDisplays = clip
        twoDisplays.screens = [
            ScreenVariant(id: "display-1", name: "Built-in", file: "original.mp4", events: [], isMain: true),
            ScreenVariant(id: "display-3", name: "LG ULTRAFINE", file: "original.mp4", events: [], isMain: false),
            ScreenVariant(id: ScreenVariant.allID, name: "Side by side", file: "original.mp4", events: [], isMain: false),
        ]
        twoDisplays.selectedScreen = "display-1"
        render(VideoEditorView(capture: twoDisplays).environment(AppState.shared), size: CGSize(width: 980, height: 640), wait: 3, to: screens.appendingPathComponent("video-editor-narrow.png"))
        writeMarkupFrames(for: shot, to: folder.appendingPathComponent("markup-frames", isDirectory: true))
        writeInstallFrames(to: folder.appendingPathComponent("install-frames", isDirectory: true))
        print("README media written to \(folder.path)")
        return 0
    }

    private static let environment = EnvironmentSnapshot(osVersion: "15.1", osBuild: "24B83", display: "2560×1440 @2x", appName: "Chrome", appVersion: "131.0", url: "stage.myapp.com/checkout", locale: "en-PT")

    // MARK: Demo captures

    /// The marks the screenshot GIF adds one by one, on the 1600×1000 sample checkout page.
    private static var demoAnnotations: [Annotation] {
        var marks: [Annotation] = []
        for (index, center) in [CGPoint(x: 92, y: 305), CGPoint(x: 92, y: 425), CGPoint(x: 940, y: 335)].enumerated() {
            var step = Annotation(tool: .step, start: center, end: .zero, color: .purple, lineWidth: 5)
            step.number = index + 1
            step.fontSize = 28
            marks.append(step)
        }
        marks.append(Annotation(tool: .blur, start: CGPoint(x: 290, y: 392), end: CGPoint(x: 560, y: 458), color: .coral, lineWidth: 5))
        marks.append(Annotation(tool: .rectangle, start: CGPoint(x: 975, y: 308), end: CGPoint(x: 1425, y: 362), color: .coral, lineWidth: 6))
        marks.append(Annotation(tool: .arrow, start: CGPoint(x: 760, y: 560), end: CGPoint(x: 965, y: 360), color: .coral, lineWidth: 6))
        var label = Annotation(tool: .text, start: CGPoint(x: 470, y: 575), end: CGPoint(x: 470, y: 575), color: .coral, lineWidth: 5)
        label.text = "Total goes negative"
        label.fontSize = 30
        marks.append(label)
        marks.append(Annotation(tool: .ellipse, start: CGPoint(x: 100, y: 845), end: CGPoint(x: 660, y: 945), color: .yellow, lineWidth: 6))
        return marks
    }

    private static func addDemoScreenshot() -> Capture? {
        guard let base = DevChecks.makeSampleScreenshot(size: CGSize(width: 1600, height: 1000)) else { return nil }
        let file = AppPaths.temporary.appendingPathComponent("readme-shot.png")
        ImageFiles.write(base, to: file, type: "public.png")
        guard let capture = try? CaptureStore.shared.add(kind: .screenshot, mediaFile: file, environment: environment) else { return nil }
        writeProject(for: capture, annotations: demoAnnotations, showBadge: true)
        return capture
    }

    private static func writeProject(for capture: Capture, annotations: [Annotation], showBadge: Bool) {
        let project = ScreenshotDocument.Project(annotations: annotations, crop: nil, showBadge: showBadge, badgeCorner: .topRight, hasCombinedBase: false)
        if let data = try? JSONEncoder().encode(project) {
            try? data.write(to: capture.projectURL)
        }
    }

    /// A 6 s clip of the checkout page: the pointer goes to the total and clicks, with an arrow and a label
    /// on the timeline.
    private static func addDemoClip() async -> Capture? {
        guard let base = DevChecks.makeSampleScreenshot(size: CGSize(width: 1600, height: 1000)) else { return nil }
        let file = AppPaths.temporary.appendingPathComponent("readme-clip.mp4")
        do {
            try await writeClip(base: base, seconds: 6, to: file)
        } catch {
            print("demo clip: \(error)")
            return nil
        }
        var events: [InputEvent] = []
        events.append(InputEvent(kind: .click, time: 1.2, x: 0.24, y: 0.33, label: "", target: "\"Email\" text field", app: "Chrome"))
        events.append(InputEvent(kind: .key, time: 2.0, x: 0, y: 0, label: "⌘ V"))
        events.append(InputEvent(kind: .click, time: 3.2, x: 0.75, y: 0.33, label: "", target: "\"Apply discount\" button", app: "Chrome"))
        events.append(InputEvent(kind: .marker, time: 3.6, x: 0, y: 0, label: ""))
        guard let capture = try? CaptureStore.shared.add(kind: .video, mediaFile: file, environment: environment, events: events, duration: 6) else { return nil }

        var project = VideoProject(duration: 6)
        project.overlays.append(VideoOverlay(kind: .arrow, span: TimeSpan(start: 3.4, end: 6), start: CGPoint(x: 0.47, y: 0.56), end: CGPoint(x: 0.6, y: 0.36)))
        project.overlays.append(VideoOverlay(kind: .text, span: TimeSpan(start: 3.4, end: 6), start: CGPoint(x: 0.3, y: 0.58), end: CGPoint(x: 0.3, y: 0.58), text: "Total goes negative"))
        project.overlays.append(VideoOverlay(kind: .blur, span: TimeSpan(start: 0, end: 6), start: CGPoint(x: 0.18, y: 0.39), end: CGPoint(x: 0.35, y: 0.46)))
        project.showBadge = true
        if let data = try? JSONEncoder().encode(project) {
            try? data.write(to: capture.projectURL)
        }
        return capture
    }

    private static func writeClip(base: CGImage, seconds: Double, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let size = CGSize(width: base.width, height: base.height)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: base.width,
            AVVideoHeightKey: base.height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: base.width,
            kCVPixelBufferHeightKey as String: base.height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        // Pointer path in image points (origin top-left): field, then the discount total.
        let path: [(time: Double, point: CGPoint)] = [
            (time: 0, point: CGPoint(x: 700, y: 760)),
            (time: 1.2, point: CGPoint(x: 380, y: 330)),
            (time: 2.4, point: CGPoint(x: 380, y: 330)),
            (time: 3.2, point: CGPoint(x: 1200, y: 330)),
            (time: 6, point: CGPoint(x: 1200, y: 330)),
        ]
        let frames = Int(seconds * 30)
        for index in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let pixelBuffer = buffer else { continue }
            let time = Double(index) / 30
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                context.draw(base, in: CGRect(origin: .zero, size: size))
                let pointer = pointerPosition(at: time, path: path)
                drawPointer(in: context, at: CGPoint(x: pointer.x, y: size.height - pointer.y))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw BufferError.exportFailed(writer.error?.localizedDescription ?? "demo clip")
        }
    }

    private static func pointerPosition(at time: Double, path: [(time: Double, point: CGPoint)]) -> CGPoint {
        for index in 1..<path.count {
            let from = path[index - 1]
            let to = path[index]
            if time <= to.time {
                let progress = (time - from.time) / max(0.001, to.time - from.time)
                let eased = progress * progress * (3 - 2 * progress)
                return CGPoint(x: from.point.x + (to.point.x - from.point.x) * eased, y: from.point.y + (to.point.y - from.point.y) * eased)
            }
        }
        return path[path.count - 1].point
    }

    /// A plain arrow pointer; `tip` is in Core Graphics coordinates (origin bottom-left).
    private static func drawPointer(in context: CGContext, at tip: CGPoint) {
        let pointer = CGMutablePath()
        pointer.move(to: tip)
        pointer.addLine(to: CGPoint(x: tip.x, y: tip.y - 34))
        pointer.addLine(to: CGPoint(x: tip.x + 9, y: tip.y - 26))
        pointer.addLine(to: CGPoint(x: tip.x + 16, y: tip.y - 40))
        pointer.addLine(to: CGPoint(x: tip.x + 22, y: tip.y - 37))
        pointer.addLine(to: CGPoint(x: tip.x + 15, y: tip.y - 24))
        pointer.addLine(to: CGPoint(x: tip.x + 26, y: tip.y - 24))
        pointer.closeSubpath()
        context.setFillColor(NSColor.black.cgColor)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(2.5)
        context.addPath(pointer)
        context.drawPath(using: .fillStroke)
    }

    /// What the player shows at 4 s: the page, the pointer on the total and the clip's marks. AVPlayer does
    /// not draw off screen, so this frame is painted into the player area of the editor picture.
    private static func clipPreviewFrame() -> CGImage? {
        guard let base = DevChecks.makeSampleScreenshot(size: CGSize(width: 1600, height: 1000)) else { return nil }
        guard let context = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        drawPointer(in: context, at: CGPoint(x: 1200, y: 1000 - 330))
        guard let withPointer = context.makeImage() else { return nil }
        var marks: [Annotation] = []
        marks.append(Annotation(tool: .blur, start: CGPoint(x: 288, y: 390), end: CGPoint(x: 560, y: 460), color: .coral, lineWidth: 5))
        marks.append(Annotation(tool: .arrow, start: CGPoint(x: 752, y: 560), end: CGPoint(x: 960, y: 360), color: .coral, lineWidth: 6))
        var label = Annotation(tool: .text, start: CGPoint(x: 480, y: 580), end: CGPoint(x: 480, y: 580), color: .coral, lineWidth: 5)
        label.text = "Total goes negative"
        label.fontSize = 30
        marks.append(label)
        return AnnotationRenderer.renderImage(base: withPointer, annotations: marks, crop: nil, badgeLines: environment.badgeLines(timeZone: TimeZone.current), badgeCorner: .topRight, badgeScale: 1.2)
    }

    /// Finds the black player area in a rendered editor picture and draws `frame` into it, fitted.
    private static func fillPlayer(in url: URL, with frame: CGImage) {
        guard let picture = ImageFiles.load(url) else { return }
        let width = picture.width
        let height = picture.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for row in 0..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                let isBlack = pixels[offset] < 3 && pixels[offset + 1] < 3 && pixels[offset + 2] < 3
                if isBlack {
                    minX = min(minX, column)
                    maxX = max(maxX, column)
                    minY = min(minY, row)
                    maxY = max(maxY, row)
                }
            }
        }
        if maxX < minX + 100 || maxY < minY + 100 { return }
        // Bitmap rows run top to bottom in memory; Core Graphics draws bottom-up.
        let area = CGRect(x: minX, y: height - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
        let scale = min(area.width / CGFloat(frame.width), area.height / CGFloat(frame.height))
        let fitted = CGSize(width: CGFloat(frame.width) * scale, height: CGFloat(frame.height) * scale)
        let target = CGRect(x: area.midX - fitted.width / 2, y: area.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
        context.interpolationQuality = .high
        context.draw(frame, in: target)
        if let result = context.makeImage() {
            ImageFiles.write(result, to: url, type: "public.png")
        }
    }

    // MARK: GIF frames

    /// The screenshot editor with the marks added one at a time. Numbered PNGs; the last one repeats so
    /// the GIF rests on the result.
    private static func writeMarkupFrames(for capture: Capture, to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let marks = demoAnnotations
        var frameNumber = 0
        for count in 0...marks.count {
            let visible = Array(marks.prefix(count))
            writeProject(for: capture, annotations: visible, showBadge: count == marks.count)
            let url = folder.appendingPathComponent(String(format: "frame-%03d.png", frameNumber))
            render(ScreenshotEditorView(capture: capture).environment(AppState.shared), size: CGSize(width: 1220, height: 780), wait: 0.6, to: url)
            frameNumber += 1
        }
        writeProject(for: capture, annotations: marks, showBadge: true)
    }

    /// The one-line install in a terminal, the way scripts/install.sh draws it: the command is typed,
    /// the logo appears, then the steps, the build spinner and the welcome.
    private static func writeInstallFrames(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let command = "curl -fsSL https://raw.githubusercontent.com/MikeKiselyov/bugbear-app/main/scripts/install.sh | bash"
        var frameNumber = 0
        func frame(_ typed: String, _ lines: [AttributedString], repeats: Int = 1) {
            for _ in 0..<repeats {
                let view = TerminalDemo(command: typed, lines: lines, showsCursor: lines.isEmpty)
                let url = folder.appendingPathComponent(String(format: "frame-%03d.png", frameNumber))
                DevChecks.render(view, size: CGSize(width: 900, height: 820), to: url)
                frameNumber += 1
            }
        }
        frame("", [])
        var typedCount = 0
        while typedCount < command.count {
            typedCount = min(command.count, typedCount + 9)
            frame(String(command.prefix(typedCount)), [])
        }

        var lines: [AttributedString] = [AttributedString("")]
        lines.append(contentsOf: installerLogo())
        lines.append(AttributedString(""))
        lines.append(Terminal.text("   ") + Terminal.text("Bug", Terminal.bear, bold: true) + Terminal.text("bear", Terminal.bug, bold: true))
        lines.append(Terminal.text("   Screenshots, recordings and a dev toolbox", Terminal.dim))
        lines.append(Terminal.text("   for people who build and test software.", Terminal.dim))
        lines.append(AttributedString(""))
        frame(command, lines, repeats: 6)

        for step in ["macOS 15.1", "Swift 6.1", "Source downloaded to ~/.bugbear"] {
            lines.append(Terminal.done(step))
            frame(command, lines, repeats: 2)
        }
        let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        let tips = [
            "The first build takes a couple of minutes. Good moment for a cup of tea ☕",
            "\(AppInfo.name) keeps the last minutes of your screen, so a bug cannot hide.",
            "Everything stays on your Mac. Nothing is uploaded anywhere.",
        ]
        for index in 0..<15 {
            var building = lines
            let seconds = index * 7
            building.append(Terminal.text("   ") + Terminal.text(spinner[index % spinner.count], Terminal.bug) + Terminal.text("  Building \(AppInfo.name) ") + Terminal.text(String(format: "%d:%02d", seconds / 60, seconds % 60), Terminal.dim))
            building.append(Terminal.text("      " + tips[index / 5], Terminal.dim))
            frame(command, building)
        }
        lines.append(Terminal.done("Built and signed (your Apple Development certificate)"))
        frame(command, lines, repeats: 2)
        lines.append(Terminal.done("Installed to /Applications/\(AppInfo.name).app"))
        frame(command, lines, repeats: 2)
        lines.append(AttributedString(""))
        lines.append(Terminal.text("   ✨ All set!", Terminal.bear, bold: true) + Terminal.text(" Look for the bear in the menu bar, top right."))
        lines.append(Terminal.text("   A short guide opens on first launch.", Terminal.dim))
        lines.append(AttributedString(""))
        lines.append(Terminal.text("   ⌥⇧1", Terminal.bug) + Terminal.text("  save the last 30 seconds"))
        lines.append(Terminal.text("   ⌥⇧4", Terminal.bug) + Terminal.text("  screenshot an area"))
        lines.append(Terminal.text("   ⌥⇧D", Terminal.bug) + Terminal.text("  dev toolbox"))
        lines.append(AttributedString(""))
        lines.append(Terminal.text("   Run this command again any time to update. Happy bug hunting! 🐻", Terminal.dim))
        frame(command, lines, repeats: 3)
    }

    /// The colored logo lines from scripts/install.sh (between "# logo-start" and "# logo-end"), so
    /// the picture always matches what the installer prints.
    private static func installerLogo() -> [AttributedString] {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("scripts/install.sh")
        guard let script = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var inside = false
        var result: [AttributedString] = []
        for rawLine in script.components(separatedBy: "\n") {
            if rawLine.hasPrefix("# logo-start") {
                inside = true
                continue
            }
            if rawLine.hasPrefix("# logo-end") { break }
            if !inside { continue }
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("\"") { line.removeFirst() }
            if line.hasSuffix("\"") { line.removeLast() }
            result.append(Terminal.parse(line))
        }
        return result
    }
    /// The editor fits the image from a main-queue block, which never runs while this code itself runs on
    /// the main queue, so the fit is done here the same way.
    private static func fitCanvases(in view: NSView) {
        for subview in view.subviews {
            fitCanvases(in: subview)
        }
        guard let canvas = view as? CanvasView, let scrollView = canvas.enclosingScrollView else { return }
        let available = scrollView.contentSize
        let size = canvas.frame.size
        if size.width <= 0 || size.height <= 0 { return }
        let scale = min((available.width - 40) / size.width, (available.height - 40) / size.height)
        let magnification = min(scale, 0.5)
        scrollView.magnification = magnification
        canvas.document.zoom = magnification
    }

    /// Renders like DevChecks.render but waits longer, for views that load media first.
    private static func render<Content: View>(_ view: Content, size: CGSize, wait: Double, to url: URL) {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height).auroraBackground().preferredColorScheme(.dark))
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        hosting.layoutSubtreeIfNeeded()
        fitCanvases(in: hosting)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }
}

/// Colors and text pieces of the install GIF, matching the installer's escape codes.
private enum Terminal {
    static let plain = Color.white.opacity(0.88)
    static let dim = Color.white.opacity(0.5)
    static let bear = Color.white
    static let bug = Color(red: 1, green: 0.37, blue: 0.37)
    static let ok = Color(red: 0.53, green: 0.84, blue: 0.53)

    static func text(_ value: String, _ color: Color = plain, bold: Bool = false) -> AttributedString {
        var piece = AttributedString(value)
        piece.foregroundColor = color
        if bold {
            piece.font = .system(size: 13, weight: .bold, design: .monospaced)
        }
        return piece
    }

    static func done(_ value: String) -> AttributedString {
        return text("   ") + text("✓", ok) + text("  " + value)
    }

    /// "${H}██${N}${C}▄${N}" from install.sh to colored text.
    static func parse(_ line: String) -> AttributedString {
        var result = AttributedString("")
        var color = plain
        var rest = Substring(line)
        while !rest.isEmpty {
            if rest.hasPrefix("${"), let close = rest.firstIndex(of: "}") {
                let name = rest[rest.index(rest.startIndex, offsetBy: 2)..<close]
                if name == "H" {
                    color = bear
                } else if name == "C" {
                    color = bug
                } else {
                    color = plain
                }
                rest = rest[rest.index(after: close)...]
                continue
            }
            let next = rest.range(of: "${")?.lowerBound ?? rest.endIndex
            result += text(String(rest[rest.startIndex..<next]), color)
            rest = rest[next...]
        }
        return result
    }
}

/// A macOS Terminal window look-alike for the install GIF.
private struct TerminalDemo: View {
    var command: String
    var lines: [AttributedString]
    var showsCursor: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 12, height: 12)
                Spacer()
                Text("Terminal").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.6))
                Spacer()
                Color.clear.frame(width: 52, height: 12)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Color(white: 0.17))

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    Text("~ % ").foregroundStyle(Color(red: 0.45, green: 0.85, blue: 0.55))
                    Text(command + (showsCursor ? "▌" : "")).foregroundStyle(Color.white)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { item in
                    if BlockRow.isBlocks(item.element) {
                        BlockRow(text: item.element)
                    } else {
                        Text(item.element).frame(height: 16)
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 13, design: .monospaced))
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(white: 0.09))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(12)
        .background(Color(white: 0.94))
    }
}

/// A logo line of half blocks (▀ ▄ █) drawn as cells, so the rows meet the way they do in a terminal.
private struct BlockRow: View {
    var text: AttributedString

    static let cellWidth: CGFloat = ("M" as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]).width
    static let cellHeight: CGFloat = 17

    static func isBlocks(_ text: AttributedString) -> Bool {
        let plain = String(text.characters)
        return plain.contains("█") || plain.contains("▀") || plain.contains("▄")
    }

    var body: some View {
        Canvas { context, _ in
            var column: CGFloat = 0
            for run in text.runs {
                let color = run.foregroundColor ?? Color.white
                for character in text[run.range].characters {
                    let x = column * BlockRow.cellWidth
                    var rect: CGRect?
                    if character == "█" {
                        rect = CGRect(x: x, y: 0, width: BlockRow.cellWidth, height: BlockRow.cellHeight)
                    } else if character == "▀" {
                        rect = CGRect(x: x, y: 0, width: BlockRow.cellWidth, height: BlockRow.cellHeight / 2)
                    } else if character == "▄" {
                        rect = CGRect(x: x, y: BlockRow.cellHeight / 2, width: BlockRow.cellWidth, height: BlockRow.cellHeight / 2)
                    }
                    if let cell = rect {
                        // A hair wider so neighbouring cells do not leave seams.
                        context.fill(Path(cell.insetBy(dx: -0.3, dy: -0.3)), with: .color(color))
                    }
                    column += 1
                }
            }
        }
        .frame(height: BlockRow.cellHeight)
    }
}
#endif
