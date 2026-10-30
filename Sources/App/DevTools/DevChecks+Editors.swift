// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AVFoundation
import AVKit
import AppKit
import AppCore
import SwiftUI

@MainActor
extension DevChecks {
    /// The five color slots: they start as the usual colors, dragging in the color panel changes the
    /// first slot, a new opening adds one on the left, and there are always five.
    static func checkRecentColors() async {
        // On scratch defaults: the person's palette is never touched.
        let domain = "\(AppInfo.name).selftest.colors.\(UUID().uuidString)"
        guard let scratch = UserDefaults(suiteName: domain) else {
            check(false, "recent colors: scratch defaults")
            return
        }
        EditorMemory.override = scratch
        defer {
            EditorMemory.override = nil
            forgetScratchDefaults(scratch, domain: domain)
        }
        RecentColors.clear()
        check(RecentColors.load() == RecentColors.defaults, "five usual colors to start with")
        var applied: [AnnotationColor] = []
        let picker = ColorPanelPicker.shared
        picker.beginForChecks { color in
            applied.append(color)
        }
        picker.pick(AnnotationColor(hex: 0x111111), wait: 0)
        try? await Task.sleep(nanoseconds: 60_000_000)
        picker.pick(AnnotationColor(hex: 0x222222), wait: 0)
        try? await Task.sleep(nanoseconds: 60_000_000)
        let afterDrag = RecentColors.load()
        check(afterDrag.first == AnnotationColor(hex: 0x222222) && afterDrag.count == RecentColors.limit && afterDrag[1] == RecentColors.defaults[0], "dragging in the color panel updates one slot", "\(afterDrag)")
        for hex in [UInt32(0x333333), 0x444444, 0x555555, 0x666666] {
            picker.endPick()
            picker.pick(AnnotationColor(hex: hex), wait: 0)
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        // A drag that passes over a color already in a slot keeps that slot.
        picker.endPick()
        let kept = RecentColors.load()[1]
        picker.pick(AnnotationColor(hex: 0x777777), wait: 0)
        try? await Task.sleep(nanoseconds: 60_000_000)
        picker.pick(kept, wait: 0)
        try? await Task.sleep(nanoseconds: 60_000_000)
        picker.pick(AnnotationColor(hex: 0x888888), wait: 0)
        try? await Task.sleep(nanoseconds: 60_000_000)
        let afterPass = RecentColors.load()
        check(afterPass.first == AnnotationColor(hex: 0x888888) && afterPass.contains(kept), "a drag over a color in the slots does not lose it", "\(afterPass)")
        picker.endPick()
        picker.pick(AnnotationColor(hex: 0x666666), wait: 0)
        try? await Task.sleep(nanoseconds: 60_000_000)
        let recent = RecentColors.load()
        check(recent.count == RecentColors.limit && recent.first == AnnotationColor(hex: 0x666666), "a new pick takes the left slot, always five", "\(recent)")
        check(applied.last == AnnotationColor(hex: 0x666666), "the picked color is applied")
    }

    static func checkVideoMarkRepair() {
        var project = EditorMemory.newVideoProject(duration: 180)
        project.timeline.trim = TimeSpan(start: 141.36, end: 180)
        project.overlays = [
            VideoOverlay(kind: .blur, span: TimeSpan(start: 179.99999, end: 180), start: CGPoint(x: 1.39, y: 1.68), end: CGPoint(x: 1.24, y: 1.90)),
            VideoOverlay(kind: .arrow, span: TimeSpan(start: 179.99, end: 180), start: CGPoint(x: 0.73, y: 1.15), end: CGPoint(x: 0.55, y: 0.95)),
        ]
        let repaired = project.repairingMarks()
        var allInside = true
        var allLong = true
        for overlay in repaired.overlays {
            let box = overlay.rect
            if box.minX < -0.0001 || box.minY < -0.0001 || box.maxX > 1.0001 || box.maxY > 1.0001 {
                allInside = false
            }
            if overlay.span.duration < 2.9 || overlay.span.end > 180.0001 {
                allLong = false
            }
        }
        check(allInside, "video marks saved off the frame come back on it")
        check(allLong, "video marks saved at the last frame last a few seconds")
    }

    static func checkBrowserURLRequest() {
        check(EnvironmentCollector.fourCharCode("cwin") == 0x6377_696E && EnvironmentCollector.fourCharCode("URL ") == 0x5552_4C20, "browser URL request codes")
        // A process that is not there answers with an error, not a hang or a crash.
        let started = Date()
        let url = EnvironmentCollector.chromiumURL(pid: 999_999)
        check(url.isEmpty && Date().timeIntervalSince(started) < EnvironmentCollector.urlTimeout + 1, "browser URL request to a closed browser gives up quietly")
    }

    static func checkArrowWithText() {
        var mark = Annotation(tool: .callout, start: CGPoint(x: 400, y: 300), end: CGPoint(x: 600, y: 320), color: .coral, lineWidth: 5)
        mark.text = "Wrong total"
        mark.fontSize = 19
        let right = AnnotationRenderer.calloutLabelBox(mark)
        check(abs(right.maxX - 400) < 0.5 && right.minY < 300 && right.maxY > 300, "arrow with text pointing right: the note ends at the tail", "\(right)")
        mark.end = CGPoint(x: 200, y: 310)
        let left = AnnotationRenderer.calloutLabelBox(mark)
        check(abs(left.minX - 400) < 0.5, "arrow with text pointing left: the note starts at the tail", "\(left)")
        mark.end = CGPoint(x: 410, y: 600)
        let down = AnnotationRenderer.calloutLabelBox(mark)
        check(abs(down.maxY - 300) < 0.5 && down.minX < 400 && down.maxX > 400, "arrow with text pointing down: the note sits above the tail", "\(down)")
        check(mark.hitTest(CGPoint(x: down.midX, y: down.midY), tolerance: 4), "a click on the note picks the arrow with text")
        check(mark.bounds.contains(down) && mark.bounds.contains(mark.end), "the selection outline holds the note and the arrow")
        check(AnnotationTool.callout.hasLabel && AnnotationTool.text.hasLabel && !AnnotationTool.arrow.hasLabel, "arrow with text takes the text size and the label fill")
        // At the picture's left edge pointing right, the note would start off the picture.
        var atEdge = Annotation(tool: .callout, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 300, y: 40), color: .coral, lineWidth: 5)
        atEdge.text = "Wrong total"
        atEdge.fontSize = 19
        atEdge.labelArea = CGRect(x: 0, y: 0, width: 800, height: 600)
        let kept = AnnotationRenderer.calloutLabelBox(atEdge)
        check(kept.minX >= 0 && kept.minY >= 0, "arrow with text from the picture's edge keeps its note on the picture", "\(kept)")
        // Nothing typed: the dimmed "Type…" shows only while typing, never in the saved picture.
        if let blank = renderTextImage([" "]) {
            let arrowOnly = Annotation(tool: .arrow, start: CGPoint(x: 220, y: 40), end: CGPoint(x: 340, y: 60), color: .coral, lineWidth: 5)
            var emptyNote = arrowOnly
            emptyNote.tool = .callout
            let emptyText = Annotation(tool: .text, start: CGPoint(x: 30, y: 30), end: CGPoint(x: 30, y: 30), color: .coral, lineWidth: 5)
            let expected = AnnotationRenderer.renderImage(base: blank, annotations: [arrowOnly], crop: nil, badgeLines: nil, badgeCorner: .topRight, badgeScale: 1)
            let saved = AnnotationRenderer.renderImage(base: blank, annotations: [emptyNote, emptyText], crop: nil, badgeLines: nil, badgeCorner: .topRight, badgeScale: 1)
            if let first = expected, let second = saved, let firstPixels = ScreenshotComparison.rgba(first, width: first.width, height: first.height), let secondPixels = ScreenshotComparison.rgba(second, width: first.width, height: first.height) {
                let difference = PixelDiff.compare(width: first.width, height: first.height, first: firstPixels, second: secondPixels)
                check(difference.changedPixels == 0, "an empty note or text leaves no placeholder in the saved picture", "\(difference.changedPixels) px")
            } else {
                check(false, "an empty note or text leaves no placeholder in the saved picture", "render failed")
            }
        }
        let tools = AnnotationTool.screenshotEditorTools
        if let arrowIndex = tools.firstIndex(of: .arrow), let calloutIndex = tools.firstIndex(of: .callout) {
            check(calloutIndex == arrowIndex + 1, "arrow with text is right after the arrow in the toolbar")
        } else {
            check(false, "arrow with text has a toolbar button")
        }
    }

    /// A new screenshot or clip opens the way the last one was left; an older capture keeps its own
    /// badge and does not change what new ones get. Runs on scratch defaults and folders.
    static func checkEditorMemory() async {
        let domain = "\(AppInfo.name).selftest.memory.\(UUID().uuidString)"
        guard let scratch = UserDefaults(suiteName: domain) else {
            check(false, "editor memory: scratch defaults")
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-memory-\(UUID().uuidString)", isDirectory: true)
        let savedOverride = AppPaths.supportOverride
        EditorMemory.override = scratch
        AppPaths.supportOverride = folder
        defer {
            EditorMemory.override = nil
            AppPaths.supportOverride = savedOverride
            forgetScratchDefaults(scratch, domain: domain)
            try? FileManager.default.removeItem(at: folder)
        }
        guard let picture = renderTextImage(["Memory"]) else {
            check(false, "editor memory: a picture")
            return
        }
        func newScreenshot() -> ScreenshotDocument? {
            let capture = Capture(id: UUID(), kind: .screenshot, createdAt: Date(), environment: EnvironmentSnapshot(), duration: 0, events: [])
            try? FileManager.default.createDirectory(at: capture.folder, withIntermediateDirectories: true)
            ImageFiles.write(picture, to: capture.mediaURL, type: "public.png")
            return ScreenshotDocument(capture: capture)
        }
        guard let first = newScreenshot() else {
            check(false, "editor memory: a screenshot document")
            return
        }
        check(first.tool == .arrow && first.color == .coral && first.stroke == .thick && !first.showBadge, "a first screenshot starts with the usual tool, color and size")
        first.tool = .rectangle
        first.color = .blue
        first.stroke = .huge
        first.textPoints = 30
        first.shapeFill = true
        first.showBadge = true
        first.badgeCorner = .bottomLeft
        first.exportFormat = .jpegMedium
        first.tool = .crop
        first.tool = .select
        guard let second = newScreenshot() else { return }
        let same = second.tool == .rectangle && second.color == .blue && second.stroke == .huge && second.textPoints == 30 && second.shapeFill && second.showBadge && second.badgeCorner == .bottomLeft && second.exportFormat == .jpegMedium
        check(same, "a new screenshot opens with the last tool, color, size, fill, badge and format", "\(second.tool) \(second.color.hex) \(second.stroke) \(second.textPoints) \(second.showBadge) \(second.badgeCorner)")

        // An older screenshot saved without a badge keeps it off, and new ones still get one.
        second.showBadge = false
        second.badgeCorner = .topLeft
        second.saveProject()
        second.showBadge = true
        second.badgeCorner = .bottomLeft
        second.showBadge = false
        second.saveProject()
        first.showBadge = true
        guard let reopened = ScreenshotDocument(capture: second.capture), let third = newScreenshot() else { return }
        check(!reopened.showBadge && third.showBadge && third.badgeCorner == .bottomLeft, "opening an older screenshot keeps its badge and leaves the next one's alone", "\(reopened.showBadge) \(third.showBadge) \(third.badgeCorner)")

        // A step guide or a comparison draws a never-edited screenshot without the remembered badge.
        guard let plain = newScreenshot() else { return }
        let drawn = ScreenshotDocument(capture: plain.capture, forEditing: false)
        check(plain.showBadge && drawn?.showBadge == false, "a step guide or comparison draws an unedited screenshot without the remembered badge")

        // + on a selected old mark resizes that mark, not the size new marks start with.
        let strokeBefore = EditorMemory.screenshotStroke
        var thin = Annotation(tool: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 60, y: 40), color: .blue, lineWidth: 2)
        thin.lineWidth = 2
        plain.tool = .rectangle
        plain.add(thin)
        plain.tool = .select
        plain.selectedId = thin.id
        plain.changeSize(by: 1)
        check(EditorMemory.screenshotStroke == strokeBefore, "+ on a selected mark leaves the size of new marks alone", "\(strokeBefore) → \(EditorMemory.screenshotStroke)")

        // Video: changed choices carry over, untouched ones keep what was remembered before.
        let fresh = EditorMemory.newVideoProject(duration: 10)
        check(fresh.showClicks && fresh.format == .mp4 && fresh.quality == .p1080, "a first clip starts with the usual choices")
        var changed = fresh
        changed.format = .gif
        changed.showKeys = false
        changed.showSteps = true
        changed.gifFramesPerSecond = 8
        EditorMemory.rememberVideoChanges(from: fresh, to: changed)
        var older = VideoProject(duration: 10)
        older.quality = .original
        var olderEdited = older
        olderEdited.showClicks = false
        EditorMemory.rememberVideoChanges(from: older, to: olderEdited)
        let next = EditorMemory.newVideoProject(duration: 20)
        let carried = next.format == .gif && !next.showKeys && next.isShowingSteps && next.gifFramesPerSecond == 8 && !next.showClicks && next.quality == .p1080 && next.timeline.sourceDuration == 20
        check(carried, "a new clip opens with the last changed choices, an older clip's other settings are not copied", "\(next.format) keys=\(next.showKeys) clicks=\(next.showClicks) \(next.quality)")

        // Undo brings back an edit; the format chosen after it stays the remembered one.
        let clip = Capture(id: UUID(), kind: .video, createdAt: Date(), environment: EnvironmentSnapshot(), duration: 2, events: [])
        try? FileManager.default.createDirectory(at: clip.folder, withIntermediateDirectories: true)
        do {
            try await writeSyntheticVideo(to: clip.mediaURL, seconds: 2, size: CGSize(width: 320, height: 200))
        } catch {
            check(false, "editor memory: a clip", "\(error)")
            return
        }
        var asGIF = EditorMemory.newVideoProject(duration: 2)
        asGIF.format = .gif
        var asMP4 = asGIF
        asMP4.format = .mp4
        EditorMemory.rememberVideoChanges(from: asGIF, to: asMP4)
        let model = VideoEditorModel(capture: clip)
        // A cut (with a checkpoint), then GIF picked in the sidebar (no checkpoint), then undo:
        // the project goes back to MP4, but the person's last choice was GIF.
        model.checkpoint()
        model.project.timeline.cuts = [TimeSpan(start: 0.5, end: 1)]
        model.projectChanged()
        model.project.format = .gif
        model.projectChanged()
        model.undo()
        check(EditorMemory.newVideoProject(duration: 2).format == .gif, "undo in the video editor does not change the remembered format", "\(EditorMemory.newVideoProject(duration: 2).format)")
    }

    static func checkDefaultMarkSize() {
        check(StrokeSize.thick.width == 7 && LiveOverlay().stroke == .thick, "drawing on the screen starts at size 7")
    }

    /// A picture placed on a screenshot is drawn in its frame, on top of the screenshot.
    static func checkPlacedImage(folder: URL) {
        guard let red = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let white = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        red.setFillColor(NSColor.red.cgColor)
        red.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        white.setFillColor(NSColor.white.cgColor)
        white.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        guard let picture = red.makeImage(), let base = white.makeImage(), let data = ImageFiles.pngData(picture) else { return }
        let file = folder.appendingPathComponent("placed-check.png")
        try? data.write(to: file)
        var placed = Annotation(tool: .image, start: CGPoint(x: 50, y: 60), end: CGPoint(x: 130, y: 120), color: .coral, lineWidth: 4)
        placed.imagePath = file.path
        guard let rendered = AnnotationRenderer.renderImage(base: base, annotations: [placed], crop: nil, badgeLines: nil, badgeCorner: .topRight, badgeScale: 1),
              let inside = pixel(rendered, at: CGPoint(x: 90, y: 90)), let outside = pixel(rendered, at: CGPoint(x: 180, y: 180)) else {
            check(false, "placed image renders")
            return
        }
        check(inside.red > 200 && inside.green < 60, "a placed picture is drawn in its frame", "\(inside)")
        check(outside.red > 245 && outside.green > 245, "the screenshot around it stays as it was", "\(outside)")
    }

    /// A filled rectangle tints what is inside it; an outline one leaves it as it was.
    static func checkShapeFill() {
        guard let context = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        guard let white = context.makeImage() else { return }
        var box = Annotation(tool: .rectangle, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 160, y: 160), color: .blue, lineWidth: 4)
        let outline = AnnotationRenderer.renderImage(base: white, annotations: [box], crop: nil, badgeLines: nil, badgeCorner: .topRight, badgeScale: 1)
        box.fill = true
        let filled = AnnotationRenderer.renderImage(base: white, annotations: [box], crop: nil, badgeLines: nil, badgeCorner: .topRight, badgeScale: 1)
        guard let outlineImage = outline, let filledImage = filled, let inside = pixel(filledImage, at: CGPoint(x: 100, y: 100)), let plain = pixel(outlineImage, at: CGPoint(x: 100, y: 100)) else {
            check(false, "shape fill renders")
            return
        }
        check(plain.red > 245 && plain.blue > 245, "outline rectangle leaves the inside as it was", "\(plain)")
        check(inside.red < 230 && inside.blue > inside.red, "filled rectangle tints the inside", "\(inside)")
        check(box.hitTest(CGPoint(x: 100, y: 100), tolerance: 4), "a filled rectangle is selected by clicking inside")
    }

    /// Each screenshot format comes out smaller as the quality goes down, and half size halves the width.
    static func checkScreenshotFormats() {
        guard let image = renderTallImage(["Total €-49.00", "Payment failed: undefined", "Discount −€98.00", "Card 4242 4242 4242 4242"]) else {
            check(false, "screenshot formats: test image")
            return
        }
        var sizes: [ScreenshotDocument.ExportFormat: Int] = [:]
        for format in ScreenshotDocument.ExportFormat.allCases {
            sizes[format] = ScreenshotDocument.encode(image, as: format)?.count ?? 0
        }
        let png = sizes[.png] ?? 0
        let high = sizes[.jpegHigh] ?? 0
        let medium = sizes[.jpegMedium] ?? 0
        let small = sizes[.jpegSmall] ?? 0
        check(png > 0 && small > 0, "screenshot formats all encode")
        check(medium < high && small < medium, "JPEG gets smaller with lower quality", "\(high) / \(medium) / \(small)")
        check((sizes[.pngHalf] ?? 0) < png, "half-size PNG is smaller", "\(sizes[.pngHalf] ?? 0) vs \(png)")
        if let data = ScreenshotDocument.encode(image, as: .pngHalf), let half = NSBitmapImageRep(data: data) {
            check(half.pixelsWide == image.width / 2, "half-size PNG is half as wide", "\(half.pixelsWide) vs \(image.width)")
        }
    }

    /// Projects saved before picked colors keep loading, and a picked color survives a save.
    static func checkAnnotationColors() {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let old = try? decoder.decode([AnnotationColor].self, from: Data(#"["coral","black"]"#.utf8))
        check(old == [.coral, .black], "old projects: palette colors load by name")
        let picked = AnnotationColor(hex: 0x12AB34)
        var roundTrip: AnnotationColor?
        if let data = try? encoder.encode([picked]) {
            check(String(decoding: data, as: UTF8.self) == ##"["#12AB34"]"##, "picked color saved as hex")
            roundTrip = (try? decoder.decode([AnnotationColor].self, from: data))?.first
        }
        check(roundTrip == picked, "picked color loads back")
        check(AnnotationColor(NSColor(hex: 0x12AB34)) == picked, "color panel color becomes the same hex")
    }
}
#endif
