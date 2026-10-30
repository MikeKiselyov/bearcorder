// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AppKit
import BugbearCore
import SwiftUI

/// The pictures and GIF frames for docs/features.md (README.md does not show them). Same rules as the rest of
/// `--readme-media`: off screen, real views, made-up demo data only.
extension ReadmeMedia {
    static func makeDocsMedia(folder: URL, clip: Capture) async {
        let screens = folder.appendingPathComponent("screens", isDirectory: true)
        writeBufferSaveFrames(clip: clip, screens: screens, to: folder.appendingPathComponent("buffer-frames", isDirectory: true))
        writeBugReportFrames(clip: clip, to: folder.appendingPathComponent("report-frames", isDirectory: true))
        await writeSpacePictures(screens: screens)
        writeMeasurePicture(to: screens.appendingPathComponent("layout-measure.png"))
        writeDesignOverlayPicture(to: screens.appendingPathComponent("layout-design.png"))
        writeCompareAndGuide(screens: screens)
    }

    /// The menu panel with the demo environment in its chips and two displays in the buffer line. The panel reads
    /// the real Mac again when it appears, so the demo environment is put back until it is there when the
    /// picture is taken. False when it never stays.
    static func renderMenu(app: AppState, to url: URL) -> Bool {
        let savedDisplayCount = app.displayCount
        defer { app.displayCount = savedDisplayCount }
        app.displayCount = 2
        // The panel's height is fixed in the app (the Space tab scrolls inside it), so the picture has the same size.
        let size = CGSize(width: 360, height: 719)
        let hosting = NSHostingView(rootView: MenuBarView().environment(app).frame(width: size.width, height: size.height).auroraBackground())
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        var isDemo = false
        for _ in 0..<6 {
            app.environmentPreview = environment
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            if app.environmentPreview == environment {
                isDemo = true
                break
            }
        }
        if !isDemo {
            print("menu picture \(url.lastPathComponent): the demo environment did not stay")
            return false
        }
        // No run loop between the check and the capture, so nothing can change it again.
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return false }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
        return true
    }

    private static func numberedFrame(_ number: Int, in folder: URL) -> URL {
        return folder.appendingPathComponent(String(format: "frame-%03d.png", number))
    }

    private static func image(from url: URL) -> Image {
        guard let picture = ImageFiles.load(url) else {
            return Image(systemName: "questionmark")
        }
        return Image(nsImage: NSImage(cgImage: picture, size: CGSize(width: CGFloat(picture.width) / 2, height: CGFloat(picture.height) / 2)))
    }

    /// A clip from two displays: what each one shows is its own page, so the display switch is a real change.
    private static func twoDisplayClip(from clip: Capture, selected: String) -> Capture {
        var twoDisplays = clip
        twoDisplays.screens = [
            ScreenVariant(id: "display-1", name: "Built-in", file: "original.mp4", events: clip.events, isMain: true),
            ScreenVariant(id: "display-3", name: "LG ULTRAFINE", file: "original.mp4", events: [], isMain: false),
            ScreenVariant(id: ScreenVariant.allID, name: "Side by side", file: "original.mp4", events: [], isMain: false),
        ]
        twoDisplays.selectedScreen = selected
        return twoDisplays
    }

    /// The second display of the demo: a terminal with the server log of the failed payment.
    private static func serverLogFrame() -> CGImage? {
        let size = CGSize(width: 1600, height: 1000)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSColor(hex: 0x14161A).setFill()
        CGRect(origin: .zero, size: size).fill()
        let lines: [(text: String, color: UInt32)] = [
            ("$ tail -f orders-service.log", 0x7EE787),
            ("10:58:09  INFO   POST /api/orders 201  34 ms", 0xC9D1D9),
            ("10:58:10  INFO   GET  /api/cart 200  12 ms", 0xC9D1D9),
            ("10:58:12  INFO   POST /api/discounts/apply 200  18 ms", 0xC9D1D9),
            ("10:58:12  WARN   discount 98.00 is larger than subtotal 49.00", 0xE3B341),
            ("10:58:12  INFO   total -49.00 EUR", 0xC9D1D9),
            ("10:58:13  ERROR  payment gateway: amount must be positive", 0xFF7B72),
            ("10:58:13  ERROR  POST /api/orders/pay 500  41 ms", 0xFF7B72),
            ("10:58:15  INFO   GET  /api/cart 200  9 ms", 0xC9D1D9),
        ]
        for (index, line) in lines.enumerated() {
            (line.text as NSString).draw(at: CGPoint(x: 60, y: 70 + CGFloat(index) * 52), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 28, weight: .regular), .foregroundColor: NSColor(hex: line.color)])
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let page = context.makeImage() else { return nil }
        // What the player shows on this display: the clip's blur and the environment badge, as on the other one.
        let blur = Annotation(tool: .blur, start: CGPoint(x: 288, y: 390), end: CGPoint(x: 560, y: 460), color: .coral, lineWidth: 5)
        return AnnotationRenderer.renderImage(base: page, annotations: [blur], crop: nil, badgeLines: environment.badgeLines(timeZone: TimeZone.current), badgeCorner: .topRight, badgeScale: 1.2)
    }

    private static func renderTwoDisplayEditor(clip: Capture, selected: String, preview: CGImage?, to url: URL) {
        render(VideoEditorView(capture: twoDisplayClip(from: clip, selected: selected)).environment(AppState.shared), size: CGSize(width: 1220, height: 800), wait: 3, to: url)
        if let frame = preview {
            fillPlayer(in: url, with: frame)
        }
    }

    // MARK: Catch a bug that already happened

    /// The menu's save buttons, the editor opening on the saved clip, then the other display picked at the top.
    private static func writeBufferSaveFrames(clip: Capture, screens: URL, to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let canvas = CGSize(width: 1220, height: 800)
        let menu = image(from: screens.appendingPathComponent("menu-capture.png"))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        DevChecks.render(menu.frame(width: canvas.width, height: canvas.height), size: canvas, to: numberedFrame(0, in: folder))

        let builtIn = folder.appendingPathComponent("editor-built-in.png")
        let other = folder.appendingPathComponent("editor-other.png")
        renderTwoDisplayEditor(clip: clip, selected: "display-1", preview: clipPreviewFrame(), to: builtIn)
        renderTwoDisplayEditor(clip: clip, selected: "display-3", preview: serverLogFrame(), to: other)
        try? FileManager.default.moveItem(at: builtIn, to: numberedFrame(1, in: folder))
        try? FileManager.default.moveItem(at: other, to: numberedFrame(2, in: folder))
    }

    // MARK: Bug reports

    /// The editor with the clicks of the clip, then the same editor with the report the button copies.
    private static func writeBugReportFrames(clip: Capture, to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let editorURL = folder.appendingPathComponent("editor.png")
        // Tall enough for the side panel down to Copy bug report; the export size estimate is not built off screen,
        // so the window ends above it.
        render(VideoEditorView(capture: clip).environment(AppState.shared), size: CGSize(width: 1220, height: 1110), wait: 3, to: editorURL)
        if let frame = clipPreviewFrame() {
            fillPlayer(in: editorURL, with: frame)
        }
        let report = BugReportBuilder.markdown(for: clip, timeMap: nil)
        let canvas = CGSize(width: 1700, height: 1110)
        for step in 0..<2 {
            let view = ReportFrame(editor: image(from: editorURL), report: step == 1 ? report : nil)
                .preferredColorScheme(.dark)
            DevChecks.render(view, size: canvas, to: numberedFrame(step, in: folder))
        }
        try? FileManager.default.removeItem(at: editorURL)
    }

    // MARK: Disk space

    /// The Review list of App caches and the Disk Space window on found projects, both on the made-up home and
    /// its made-up disk.
    private static func writeSpacePictures(screens: URL) async {
        let extraFiles: [DevChecks.MadeUpFile] = [
            DevChecks.MadeUpFile(path: "Library/Caches/com.example.design/data", bytes: 42_000_000),
            DevChecks.MadeUpFile(path: "Library/Caches/com.example.chat/data", bytes: 17_000_000),
            DevChecks.MadeUpFile(path: "Library/Caches/com.example.notes/data", bytes: 3_000_000),
            DevChecks.MadeUpFile(path: "Projects/bugbear-site/node_modules/lib/blob", bytes: 3_000_000),
            DevChecks.MadeUpFile(path: "Projects/bugbear-site/package.json", text: "{}"),
            DevChecks.MadeUpFile(path: "Projects/ml-notebooks/.venv/lib/blob", bytes: 2_000_000),
            DevChecks.MadeUpFile(path: "Projects/ml-notebooks/.venv/pyvenv.cfg", text: "home = /usr/bin"),
            DevChecks.MadeUpFile(path: "Projects/ml-notebooks/pyproject.toml", text: "[project]", daysOld: 200),
        ]
        await DevChecks.withMadeUpSpaceHome(extraFiles: extraFiles) {
            let space = SpaceModel.shared
            let savedSection = space.section
            defer { space.section = savedSection }
            space.section = .cleanUp
            let size = CGSize(width: 900, height: 560)

            // Ticked the way a person would: every other row.
            guard let caches = CleanupCategory.all.first(where: { category in category.id == "appCaches" }), let review = await space.openReview(for: caches) else {
                print("space review picture: the list did not load")
                return
            }
            for index in review.rows.indices {
                review.rows[index].isChecked = index % 2 == 0
            }
            space.showReview("appCaches")
            render(SpaceView().environment(AppState.shared), size: size, wait: 1.5, to: screens.appendingPathComponent("space-review-category.png"))

            space.showReview(SpaceModel.projectsID)
            render(SpaceView().environment(AppState.shared), size: CGSize(width: 1000, height: 560), wait: 1.5, to: screens.appendingPathComponent("space-window-find.png"))
            space.showReview(nil)
        }
    }

    // MARK: Checking a layout

    /// A page of the demo on a plain AppKit view, the way renderAppKit lays out the area pickers.
    private static func pageContainer(size: CGSize) -> (container: NSView, window: NSWindow)? {
        guard let page = DevChecks.makeSampleScreenshot(size: CGSize(width: 1600, height: 1000)) else { return nil }
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.contents = page
        container.layer?.contentsGravity = .resize
        let window = NSWindow(contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = container
        return (container: container, window: window)
    }

    private static func write(_ container: NSView, to url: URL) {
        guard let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds) else { return }
        container.cacheDisplay(in: container.bounds, to: bitmap)
        if let picture = bitmap.cgImage {
            ImageFiles.write(picture, to: url, type: "public.png")
        }
    }

    private static func mouseEvent(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat, height: CGFloat, window: NSWindow) -> NSEvent? {
        return NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: height - y), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    }

    /// Measure on screen: the real ruler view after a drag over the order summary.
    private static func writeMeasurePicture(to url: URL) {
        let size = CGSize(width: 1280, height: 800)
        guard let page = pageContainer(size: size) else { return }
        let ruler = RulerView(frame: page.container.bounds)
        ruler.pixelScale = 2
        page.container.addSubview(ruler)
        guard let down = mouseEvent(.leftMouseDown, x: 760, y: 104, height: size.height, window: page.window), let drag = mouseEvent(.leftMouseDragged, x: 1160, y: 360, height: size.height, window: page.window) else { return }
        ruler.mouseDown(with: down)
        ruler.mouseDragged(with: drag)
        write(page.container, to: url)
    }

    /// Design overlay: a design export at half opacity a few points off the page, and the real controls panel.
    private static func writeDesignOverlayPicture(to url: URL) {
        let size = CGSize(width: 1280, height: 800)
        guard let page = pageContainer(size: size), let design = DevChecks.makeSampleScreenshot(size: CGSize(width: 1600, height: 1000)) else { return }
        let designView = OverlayImageView(frame: CGRect(x: 14, y: -10, width: size.width, height: size.height))
        designView.image = NSImage(cgImage: design, size: size)
        designView.wantsLayer = true
        designView.alphaValue = 0.5
        page.container.addSubview(designView)
        let overlay = DesignOverlay.shared
        let savedOpacity = overlay.opacity
        overlay.opacity = 0.5
        let controls = NSHostingView(rootView: DesignOverlayControls(overlay: overlay))
        let controlsSize = controls.fittingSize
        controls.frame = CGRect(x: size.width - controlsSize.width - 24, y: 24, width: controlsSize.width, height: controlsSize.height)
        page.container.addSubview(controls)
        page.container.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        write(page.container, to: url)
        overlay.opacity = savedOpacity
    }

    // MARK: Recent captures

    /// The checkout page after the fix: the discount and total are right and the error is gone.
    private static func fixedCheckoutPage(from base: CGImage) -> CGImage? {
        let size = CGSize(width: base.width, height: base.height)
        guard let context = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(base, in: CGRect(origin: .zero, size: size))
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSColor.white.setFill()
        CGRect(x: 985, y: 262, width: 440, height: 110).fill()
        func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ fontSize: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) {
            (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: weight), .foregroundColor: color])
        }
        text("Discount                       −€4.90", 990, 270, 24, .regular, NSColor(hex: 0x1C1D20))
        text("Total                            €44.10", 990, 320, 26, .bold, NSColor(hex: 0x1C1D20))
        NSColor(hex: 0xF6F7F9).setFill()
        CGRect(x: 110, y: 850, width: 580, height: 90).fill()
        NSColor(hex: 0xE6F5EA).setFill()
        NSBezierPath(roundedRect: CGRect(x: 120, y: 860, width: 520, height: 70), xRadius: 10, yRadius: 10).fill()
        text("Order placed", 145, 880, 26, .regular, NSColor(hex: 0x16692E))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    private static func addScreenshot(_ picture: CGImage, annotations: [Annotation] = []) -> Capture? {
        let file = AppPaths.temporary.appendingPathComponent("docs-shot-\(UUID().uuidString).png")
        ImageFiles.write(picture, to: file, type: "public.png")
        guard let capture = try? CaptureStore.shared.add(kind: .screenshot, mediaFile: file, environment: environment) else { return nil }
        writeProject(for: capture, annotations: annotations, showBadge: false)
        return capture
    }

    private static func cropped(_ picture: CGImage, _ area: CGRect) -> CGImage {
        return picture.cropping(to: area) ?? picture
    }

    /// Compare on the page before and after a fix, and a step guide of three cuts of the page.
    private static func writeCompareAndGuide(screens: URL) {
        guard let base = DevChecks.makeSampleScreenshot(size: CGSize(width: 1600, height: 1000)), let fixed = fixedCheckoutPage(from: base) else { return }
        guard let before = addScreenshot(base), let after = addScreenshot(fixed) else { return }
        render(CompareView(before: before, after: after).environment(AppState.shared), size: CGSize(width: 1220, height: 700), wait: 2, to: screens.appendingPathComponent("compare.png"))

        let discount = Annotation(tool: .rectangle, start: CGPoint(x: 75, y: 160), end: CGPoint(x: 545, y: 208), color: .coral, lineWidth: 5)
        guard let form = addScreenshot(cropped(base, CGRect(x: 0, y: 100, width: 760, height: 380))),
              let summary = addScreenshot(cropped(base, CGRect(x: 900, y: 100, width: 600, height: 380)), annotations: [discount]),
              let failure = addScreenshot(cropped(base, CGRect(x: 0, y: 820, width: 760, height: 140))) else { return }
        let guide = StepGuideModel(captures: [form, summary, failure])
        guide.title = "Discount makes the total negative"
        let captions = ["Fill in the email and the card", "Apply the discount code", "Press Pay: the payment fails"]
        for index in guide.steps.indices {
            guide.steps[index].caption = captions[index]
        }
        var blocks: [(image: CGImage, caption: String)] = []
        for step in guide.steps {
            blocks.append((image: step.image, caption: step.caption))
        }
        if let page = StepGuideRenderer.longImage(title: guide.title, steps: blocks) {
            ImageFiles.write(page, to: screens.appendingPathComponent("step-guide.png"), type: "public.png")
        }
    }
}

/// The video editor next to the report the Copy bug report button puts on the clipboard.
private struct ReportFrame: View {
    var editor: Image
    var report: String?

    var body: some View {
        HStack(spacing: 0) {
            editor
            ZStack(alignment: .topLeading) {
                Color.clear
                if let text = report {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("On the clipboard")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.55))
                        Text(text)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 60)
                    .padding(.horizontal, 20)
                }
            }
            .frame(width: 480)
        }
    }
}
#endif
