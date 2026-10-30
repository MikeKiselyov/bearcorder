// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AVFoundation
import AVKit
import AppKit
import AppCore
import SwiftUI

/// Developer checks that need no permissions, run from the command line:
///   .build/debug/App --self-test <folder>   media pipeline checks, writes sample outputs
///   .build/debug/App --snapshot <folder>    renders every screen to PNG
@MainActor
enum DevChecks {
    private static var failures: [String] = []

    static func renderTextImage(_ lines: [String]) -> CGImage? {
        let size = CGSize(width: 900, height: 220)
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.white.setFill()
            rect.fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black]
            for (index, line) in lines.enumerated() {
                NSAttributedString(string: line, attributes: attributes).draw(at: CGPoint(x: 30, y: 30 + Double(index) * 80))
            }
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// One pixel of an image, top-left origin.
    static func pixel(_ image: CGImage, at point: CGPoint) -> (red: Int, green: Int, blue: Int)? {
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            let flippedY = CGFloat(image.height) - point.y - 1
            context.draw(image, in: CGRect(x: -point.x, y: -flippedY, width: CGFloat(image.width), height: CGFloat(image.height)))
            return true
        }
        if !drawn { return nil }
        return (red: Int(bytes[0]), green: Int(bytes[1]), blue: Int(bytes[2]))
    }

    /// A tall white page with one text line every 60 px.
    static func renderTallImage(_ lines: [String]) -> CGImage? {
        let size = CGSize(width: 700, height: CGFloat(lines.count) * 60 + 40)
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.white.setFill()
            rect.fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.black]
            for (index, line) in lines.enumerated() {
                NSAttributedString(string: line, attributes: attributes).draw(at: CGPoint(x: 20, y: 20 + Double(index) * 60))
            }
            return true
        }
        var proposed = CGRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &proposed, context: nil, hints: [.ctm: AffineTransform.identity])
    }

    static func check(_ condition: Bool, _ name: String, _ detail: String = "") {
        if condition {
            print("PASS  \(name)")
        } else {
            print("FAIL  \(name) \(detail)")
            failures.append(name)
        }
    }

    // MARK: Self test

    static func selfTest(folder: URL) async -> Int32 {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        failures = []
        checkAnnotationColors()
        checkScreenshotFormats()
        await checkRecentColors()
        checkShortcutWords()
        checkShapeFill()
        checkTooltipSize(folder: folder)
        checkPlacedImage(folder: folder)
        checkSameFile(folder: folder)
        checkFeedback(folder: folder)
        checkRecordingClock()
        checkCleanupCategories()
        await checkHuggingFaceTokensStay()
        await checkWholeFolderCaches()
        checkWhatsNewPictures()
        checkLocalization(folder: folder)
        checkPlayerView()
        checkCrashClipMigration()
        checkCleanupSettings()
        await checkSpaceReview()
        checkSpaceSkipTexts()
        checkDefaultMarkSize()
        checkSystemActionsRecord()
        checkAreaGrip()
        checkHistoryCardMenu()
        checkLateSystemLog()
        checkCaptureStoreSkipsBrokenCapture(folder: folder)
        await checkClipReachesSaveAfterStill(folder: folder)
        await checkStillScreenSegmentsAreContiguous(folder: folder)
        await checkSingleFrameSegmentKeepsItsTime(folder: folder)
        await checkSaveLeavesNoGapOnStillScreen(folder: folder)
        await checkBufferHeldSeconds(folder: folder)
        checkBufferConfigurationPerDisplay()
        checkAreaMovedGrowsNativeSet()
        await checkClipAcrossSizeChange(folder: folder)
        await checkPopUpChoices()
        await checkTextInput()
        checkRegionPickerButtons()
        checkControlTreeCoordinates()
        checkFieldSettingsOnOldCaptures()
        checkArrowWithText()
        checkBrowserURLRequest()
        checkVideoMarkRepair()
        checkCopyReportButtonFits()
        await checkEditorMemory()
        checkKeyLabels()
        checkAutomationToken()
        checkFirstVersionFiles()
        checkReportFollowsEdits()
        checkSavedNamesAndShortcuts()
        checkStepCaptions()

        // 1. Synthetic 6 s clip with a moving box and a 440 Hz tone.
        let video = folder.appendingPathComponent("synthetic-video.mov")
        let audio = folder.appendingPathComponent("synthetic-audio.caf")
        let clip = folder.appendingPathComponent("synthetic-clip.mp4")
        do {
            try await writeSyntheticVideo(to: video, seconds: 6, size: CGSize(width: 1280, height: 720))
            try writeSineAudio(to: audio, seconds: 6)
            let composition = AVMutableComposition()
            let videoAsset = AVURLAsset(url: video)
            let audioAsset = AVURLAsset(url: audio)
            let videoTrack = try await videoAsset.loadTracks(withMediaType: .video)[0]
            let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio)[0]
            let range = try await videoTrack.load(.timeRange)
            try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?.insertTimeRange(range, of: videoTrack, at: .zero)
            // A second audio track checks that the exporter mixes system + mic into one.
            try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?.insertTimeRange(range, of: audioTrack, at: .zero)
            try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?.insertTimeRange(range, of: audioTrack, at: .zero)
            try await AssetExporter.export(asset: composition, videoComposition: nil, options: .init(renderSize: CGSize(width: 1280, height: 720)), to: clip)
            let exported = AVURLAsset(url: clip)
            let duration = try await exported.load(.duration).seconds
            let audioTracks = try await exported.loadTracks(withMediaType: .audio)
            check(abs(duration - 6) < 0.2, "AssetExporter keeps duration", "got \(duration)")
            check(audioTracks.count == 1, "AssetExporter mixes audio tracks into one", "got \(audioTracks.count)")
        } catch {
            check(false, "synthetic clip", "\(error)")
            return 1
        }

        // 2. Editor pipeline: trim, cut, slow motion, freeze, overlays, clicks, keys, badge.
        var project = VideoProject(duration: 6)
        project.timeline.trim = TimeSpan(start: 0.5, end: 5.5)
        project.timeline.cuts = [TimeSpan(start: 2, end: 2.5)]
        project.timeline.speeds = [SpeedEdit(span: TimeSpan(start: 3, end: 4), factor: 0.5)]
        project.timeline.freezes = [FreezeEdit(at: 1, duration: 1)]
        project.overlays = [
            VideoOverlay(kind: .text, span: TimeSpan(start: 0.5, end: 5.5), start: CGPoint(x: 0.05, y: 0.08), end: CGPoint(x: 0.05, y: 0.08), text: "Total is negative", color: .coral),
            VideoOverlay(kind: .text, span: TimeSpan(start: 0.5, end: 5.5), start: CGPoint(x: 0.5, y: 0.08), end: CGPoint(x: 0.5, y: 0.08), text: "No background", color: .white, clearBackground: true),
            VideoOverlay(kind: .arrow, span: TimeSpan(start: 0.5, end: 5.5), start: CGPoint(x: 0.3, y: 0.3), end: CGPoint(x: 0.5, y: 0.5), color: .yellow),
            VideoOverlay(kind: .rectangle, span: TimeSpan(start: 0.5, end: 5.5), start: CGPoint(x: 0.55, y: 0.55), end: CGPoint(x: 0.8, y: 0.75), color: .coral),
            VideoOverlay(kind: .blur, span: TimeSpan(start: 0.5, end: 5.5), start: CGPoint(x: 0.05, y: 0.7), end: CGPoint(x: 0.35, y: 0.95)),
        ]
        project.showBadge = true
        let events = [
            InputEvent(kind: .click, time: 1.6, x: 0.5, y: 0.5, label: ""),
            InputEvent(kind: .key, time: 1.5, x: 0, y: 0, label: "⌘ Enter"),
        ]
        var environment = EnvironmentSnapshot(osVersion: "15.1", osBuild: "24B83", display: "2560×1440 @2x", appName: "Chrome", appVersion: "131.0", url: "stage.myapp.com/checkout")
        environment.capturedAt = Date(timeIntervalSince1970: 1_792_839_492)
        let expected = project.timeline.outputDuration
        do {
            let output = try await VideoCompositor.build(asset: AVURLAsset(url: clip), project: project, events: events, environment: environment)
            check(abs(output.duration - expected) < 0.01, "Compositor output duration matches timeline", "\(output.duration) vs \(expected)")
            let mp4 = folder.appendingPathComponent("edited.mp4")
            try await VideoCompositor.exportMP4(output, quality: .p720, to: mp4, progress: nil)
            let exported = AVURLAsset(url: mp4)
            let duration = try await exported.load(.duration).seconds
            check(abs(duration - expected) < 0.25, "Edited MP4 duration", "got \(duration), expected \(expected)")
            let tracks = try await exported.loadTracks(withMediaType: .video)
            let size = try await tracks[0].load(.naturalSize)
            check(size.height == 720, "Edited MP4 is 720p", "\(size)")
            let audioTracks = try await exported.loadTracks(withMediaType: .audio)
            check(audioTracks.count == 1, "Edited MP4 keeps audio")
            // The size shown in the quality menu is an upper estimate: the file must not be bigger.
            // The size in the quality menu follows how densely the source is encoded.
            let preset = SizeBudget.preset(sourceWidth: output.renderSize.width, sourceHeight: output.renderSize.height, maxHeight: 720)
            var sourcePerPixel: Double?
            if let sourceTrack = try await AVURLAsset(url: clip).loadTracks(withMediaType: .video).first {
                let rate = try await sourceTrack.load(.estimatedDataRate)
                let natural = try await sourceTrack.load(.naturalSize)
                sourcePerPixel = Double(rate) / Double(natural.width * natural.height)
            }
            let bitrate = SizeBudget.expectedVideoBitrate(presetBitrate: preset.videoBitrate, sourceBitsPerPixelSecond: sourcePerPixel, width: preset.width, height: preset.height)
            let estimate = SizeBudget.estimatedBytes(videoBitrate: bitrate, duration: expected, hasAudio: true)
            let actual = Double((try? FileManager.default.attributesOfItem(atPath: mp4.path)[.size] as? Int) ?? 0)
            check(actual > estimate / 2.5 && actual < estimate * 2.5, "720p file size is close to the shown estimate", "\(Int(actual)) vs \(Int(estimate))")
            print("      720p estimate \(Int(estimate)) bytes, file \(Int(actual)) bytes")

            let limited = folder.appendingPathComponent("edited-1mb.mp4")
            try await VideoCompositor.exportMP4(output, quality: .original, sizeLimitMB: 1, to: limited, progress: nil)
            let limitedBytes = (try? FileManager.default.attributesOfItem(atPath: limited.path)[.size] as? NSNumber)?.intValue ?? 0
            check(limitedBytes > 0 && limitedBytes <= 1_000_000, "MP4 with a 1 MB limit fits", "\(limitedBytes) bytes")

            // Frame with all overlays (output 1.7 s → source 1.2 s, right after the click).
            let generator = AVAssetImageGenerator(asset: exported)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let frame = try await generator.image(at: CMTime(seconds: 2.15, preferredTimescale: 600)).image
            ImageFiles.write(frame, to: folder.appendingPathComponent("edited-frame.png"), type: "public.png")
            check(frame.width > 0, "Edited frame renders")

            let gif = folder.appendingPathComponent("edited.gif")
            try await VideoCompositor.exportGIF(output, framesPerSecond: 8, to: gif, progress: nil)
            let source = CGImageSourceCreateWithURL(gif as CFURL, nil)
            let frames = source.map { CGImageSourceGetCount($0) } ?? 0
            check(frames >= Int(expected * 8) - 2, "GIF frame count", "got \(frames)")
        } catch {
            check(false, "editor pipeline", "\(error)")
        }

        // 2a. Crop: the video is only the picked part, and a mark stays on the picture under it.
        do {
            var cropped = VideoProject(duration: 6)
            cropped.crop = CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
            // A thick box whose left side runs through the middle of the kept part's left half.
            cropped.overlays = [
                VideoOverlay(kind: .rectangle, span: TimeSpan(start: 0, end: 6), start: CGPoint(x: 0.6, y: 0.6), end: CGPoint(x: 0.9, y: 0.9), color: .coral, scale: 4),
            ]
            let output = try await VideoCompositor.build(asset: AVURLAsset(url: clip), project: cropped, events: [], environment: EnvironmentSnapshot())
            check(output.renderSize == CGSize(width: 640, height: 360), "a crop of a quarter of 1280×720 is 640×360", "\(output.renderSize)")
            let whole = try await VideoCompositor.build(asset: AVURLAsset(url: clip), project: cropped, events: [], environment: EnvironmentSnapshot(), showsWholeFrame: true)
            check(whole.renderSize == CGSize(width: 1280, height: 720) && whole.crop == VideoCrop.whole, "picking the crop shows the whole frame", "\(whole.renderSize)")
            let mp4 = folder.appendingPathComponent("cropped.mp4")
            try await VideoCompositor.exportMP4(output, quality: .original, to: mp4, progress: nil)
            let exported = AVURLAsset(url: mp4)
            let size = try await exported.loadTracks(withMediaType: .video)[0].load(.naturalSize)
            check(size == CGSize(width: 640, height: 360), "the cropped file is 640×360", "\(size)")
            let generator = AVAssetImageGenerator(asset: exported)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let frame = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
            ImageFiles.write(frame, to: folder.appendingPathComponent("cropped-frame.png"), type: "public.png")
            // Frame x 0.6 is 0.2 of the kept part: 128 px; frame y 0.75 is the middle of the box: 180 px.
            let onLine = pixel(frame, at: CGPoint(x: 128, y: 180))
            let isCoral = (onLine?.red ?? 0) > 200 && (onLine?.green ?? 255) < 160 && (onLine?.blue ?? 255) < 140
            check(isCoral, "a mark stays on the picture through the crop", "\(String(describing: onLine))")
        } catch {
            check(false, "crop pipeline", "\(error)")
        }

        // 2b. Every edit kind on a constant-rate and a variable-rate clip (the buffer is variable-rate).
        let variable = folder.appendingPathComponent("synthetic-vfr.mov")
        do {
            try await writeSyntheticVideo(to: variable, seconds: 7, size: CGSize(width: 1662, height: 1080), variableRate: true)
        } catch {
            check(false, "variable-rate clip", "\(error)")
        }
        for (name, source) in [("constant-rate", clip), ("variable-rate", variable)] {
            let status = await exportCheck(file: source, folder: folder.appendingPathComponent("variants-\(name)"))
            check(status == 0, "all edit kinds export on a \(name) clip")
        }

        // 3. Screenshot rendering with every tool, crop and badge.
        if let base = makeSampleScreenshot(size: CGSize(width: 1600, height: 1000)) {
            ImageFiles.write(base, to: folder.appendingPathComponent("screenshot-base.png"), type: "public.png")
            var annotations: [Annotation] = []
            annotations.append(Annotation(tool: .arrow, start: CGPoint(x: 700, y: 520), end: CGPoint(x: 980, y: 300), color: .coral, lineWidth: 6))
            annotations.append(Annotation(tool: .rectangle, start: CGPoint(x: 1000, y: 260), end: CGPoint(x: 1400, y: 330), color: .coral, lineWidth: 6))
            annotations.append(Annotation(tool: .ellipse, start: CGPoint(x: 120, y: 700), end: CGPoint(x: 420, y: 820), color: .blue, lineWidth: 5))
            var text = Annotation(tool: .text, start: CGPoint(x: 620, y: 560), end: CGPoint(x: 620, y: 560), color: .coral, lineWidth: 5)
            text.text = "Total is negative"
            text.fontSize = 26
            annotations.append(text)
            for number in 1...3 {
                var step = Annotation(tool: .step, start: CGPoint(x: 160 + CGFloat(number) * 90, y: 200), end: .zero, color: .purple, lineWidth: 5)
                step.number = number
                step.fontSize = 28
                annotations.append(step)
            }
            annotations.append(Annotation(tool: .blur, start: CGPoint(x: 280, y: 395), end: CGPoint(x: 540, y: 455), color: .coral, lineWidth: 5))
            annotations.append(Annotation(tool: .magnifier, start: CGPoint(x: 1180, y: 700), end: CGPoint(x: 1300, y: 780), color: .yellow, lineWidth: 5))
            var pen = Annotation(tool: .highlighter, start: .zero, end: .zero, color: .yellow, lineWidth: 5)
            pen.points = [CGPoint(x: 700, y: 900), CGPoint(x: 800, y: 880), CGPoint(x: 900, y: 905), CGPoint(x: 1000, y: 885)]
            annotations.append(pen)
            let full = AnnotationRenderer.renderImage(base: base, annotations: annotations, crop: nil, badgeLines: environment.badgeLines(timeZone: TimeZone(identifier: "UTC")!), badgeCorner: .topRight, badgeScale: 1.2)
            check(full?.width == 1600 && full?.height == 1000, "Screenshot render keeps size")
            if let image = full {
                ImageFiles.write(image, to: folder.appendingPathComponent("screenshot-annotated.png"), type: "public.png")
            }
            let cropped = AnnotationRenderer.renderImage(base: base, annotations: annotations, crop: CGRect(x: 100, y: 150, width: 800, height: 500), badgeLines: nil, badgeCorner: .topRight, badgeScale: 1)
            check(cropped?.width == 800 && cropped?.height == 500, "Screenshot crop size")
            let stitched = ScreenshotCapture.stitchHorizontally([base, base], gap: 0)
            check(stitched?.width == 3200 && stitched?.height == 1000, "Stitch two displays")
        }

        // 3b. Text on a label and text with a transparent background.
        if let white = renderTextImage([]) {
            var label = Annotation(tool: .text, start: CGPoint(x: 40, y: 40), end: CGPoint(x: 40, y: 40), color: .coral, lineWidth: 5)
            label.text = "Checkout 502"
            label.fontSize = 40
            var clear = label
            clear.clearBackground = true
            let corner = CGPoint(x: 44, y: 44)
            let labelImage = AnnotationRenderer.renderImage(base: white, annotations: [label], crop: nil, badgeLines: nil, badgeCorner: .topRight, badgeScale: 1)
            let clearImage = AnnotationRenderer.renderImage(base: white, annotations: [clear], crop: nil, badgeLines: nil, badgeCorner: .topRight, badgeScale: 1)
            let labelCorner = labelImage.flatMap { image in pixel(image, at: corner) }
            let clearCorner = clearImage.flatMap { image in pixel(image, at: corner) }
            check(labelCorner != nil && labelCorner!.green < 150, "Text label fills its box", "\(String(describing: labelCorner))")
            check(clearCorner != nil && clearCorner!.red > 240 && clearCorner!.green > 240 && clearCorner!.blue > 240, "Transparent text leaves the picture visible", "\(String(describing: clearCorner))")
            if let image = clearImage {
                ImageFiles.write(image, to: folder.appendingPathComponent("text-transparent.png"), type: "public.png")
                let lines = (try? await TextRecognizer.recognize(image)) ?? []
                let text = TextRecognizer.text(of: lines)
                check(text.contains("Checkout") && text.contains("502"), "Transparent text stays readable", text)
            }
            var data = try? JSONEncoder().encode(label)
            var decoded = data.flatMap { encoded in try? JSONDecoder().decode(Annotation.self, from: encoded) }
            check(decoded != nil && decoded!.hasClearBackground == false, "Old marks keep their label")
            data = try? JSONEncoder().encode(clear)
            decoded = data.flatMap { encoded in try? JSONDecoder().decode(Annotation.self, from: encoded) }
            check(decoded?.hasClearBackground == true, "Transparent text is saved")
        } else {
            check(false, "Render white image")
        }

        // 4. Click placement for side-by-side displays and a recorded area.
        let left = ClipLayout.Display(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), x: 0, width: 1920)
        let right = ClipLayout.Display(frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), x: 1920, width: 1600)
        let layout = ClipLayout(displays: [left, right], totalWidth: 3520)
        let point = layout.normalizedPoint(forGlobal: CGPoint(x: 1440 + 960, y: 540))
        check(point != nil && abs(point!.x - (1920 + 800) / 3520) < 0.001 && abs(point!.y - 0.5) < 0.001, "Click mapping across displays")
        // The bottom-right quarter of the left display.
        let regionLayout = ClipLayout(displays: [left], totalWidth: 1920, area: CGRect(x: 720, y: 0, width: 720, height: 450))
        let inside = regionLayout.normalizedPoint(forGlobal: CGPoint(x: 1080, y: 225))
        check(inside != nil && abs(inside!.x - 0.5) < 0.001 && abs(inside!.y - 0.5) < 0.001, "Click mapping inside a region")
        check(regionLayout.normalizedPoint(forGlobal: CGPoint(x: 100, y: 800)) == nil, "Clicks outside the region are dropped")

        // 5. Recording pauses become kept ranges.
        let session = RecordingSession(startTime: 100)
        check(session.keptRanges(until: 110).count == 1, "Recording without pauses")

        // 6. Logo renders at every icon size.
        let iconset = folder.appendingPathComponent("Logo.iconset")
        try? Logo.writeIconset(to: iconset)
        let icons = (try? FileManager.default.contentsOfDirectory(atPath: iconset.path)) ?? []
        check(icons.count == 10, "Logo iconset sizes", "got \(icons.count)")

        // 7. Text recognition on a rendered error message, two lines.
        if let textImage = renderTextImage(["Error 502: order A7-4521 failed", "Retry later"]) {
            let lines = (try? await TextRecognizer.recognize(textImage)) ?? []
            let text = TextRecognizer.text(of: lines)
            check(text.contains("A7-4521") && text.contains("502"), "Text recognition keeps IDs", text)
            check(text.hasPrefix("Error") && text.hasSuffix("Retry later"), "Recognized lines in reading order", text)
        } else {
            check(false, "Render text image")
        }

        // 8. + and - size steps stay in range.
        check(StrokeSize.medium.stepped(1) == .thick && StrokeSize.giant.stepped(1) == .giant && StrokeSize.hairline.stepped(-1) == .hairline, "Line thickness steps")
        check(TextSizes.stepped(from: 19, 1) == 22 && TextSizes.stepped(from: 100, 1) == 100 && TextSizes.stepped(from: 12, -1) == 12, "Text size steps")
        var sizedOverlay = VideoOverlay(kind: .arrow, span: TimeSpan(start: 0, end: 1), start: .zero, end: CGPoint(x: 1, y: 1))
        check(sizedOverlay.steppedScale(1) == 1.25 && sizedOverlay.steppedScale(-1) == 0.75, "Video mark size steps")
        sizedOverlay.scale = 4
        check(sizedOverlay.steppedScale(1) == 4, "Video mark size stops at 400%")

        // 9. Shortcuts: defaults, recording a key press, conflicts.
        check(HotKeyAction.saveMinute.defaultShortcut?.display == "⌥⇧2", "Default shortcut text")
        if let press = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0, windowNumber: 0, context: nil, characters: "K", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40) {
            check(Shortcut.from(press)?.display == "⇧⌘K", "Shortcut from a key press", Shortcut.from(press)?.display ?? "nil")
        }
        if let plain = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40) {
            check(Shortcut.from(plain) == nil, "Plain keys are not shortcuts")
        }
        let taken = HotKeyAction.saveMinute.defaultShortcut!
        check(HotKeySettings.shared.owner(of: taken, except: .draw) == .saveMinute, "Shortcut conflicts are found")

        // 10. Step guide and before/after images from synthetic screenshots.
        if let first = renderTextImage(["Step one: open settings"]), let second = renderTextImage(["Step two: press Pay", "Error 502"]) {
            let steps: [(image: CGImage, caption: String)] = [(image: first, caption: "Open settings"), (image: second, caption: "")]
            let guide = StepGuideRenderer.longImage(title: "How to reproduce", steps: steps)
            check(guide?.width == 1400 && (guide?.height ?? 0) > first.height + second.height, "Step guide image", "\(guide?.width ?? 0)×\(guide?.height ?? 0)")
            let pdfURL = folder.appendingPathComponent("guide.pdf")
            let wrote = StepGuideRenderer.writePDF(title: "How to reproduce", steps: steps, to: pdfURL)
            let pages = CGPDFDocument(pdfURL as CFURL)?.numberOfPages ?? 0
            check(wrote && pages == 2, "Step guide PDF has a page per step", "\(pages) pages")
            if let pixelsBefore = ScreenshotComparison.rgba(first, width: first.width, height: first.height), let pixelsAfter = ScreenshotComparison.rgba(second, width: first.width, height: first.height), let resized = ScreenshotComparison.rgba(second, width: first.width, height: first.height) {
                let result = PixelDiff.compare(width: first.width, height: first.height, first: pixelsBefore, second: pixelsAfter)
                check(!result.regions.isEmpty && resized.count == pixelsAfter.count, "Before/after finds changed areas", "\(result.regions.count) areas")
                let output = ScreenshotComparison.Output(before: first, after: first, result: result, scale: 1)
                let boxed = ScreenshotComparison.changesImage(output)
                let combined = ScreenshotComparison.sideBySideImage(output, changes: boxed)
                check(boxed != nil && (combined?.width ?? 0) > first.width * 2, "Before | After image")
            }
        }

        // 11. Scrolling screenshot: frames cut from a tall page glue back into the page.
        var pageLines: [String] = []
        for index in 1...40 {
            pageLines.append("Row \(index): order A7-\(4500 + index) · status \(index % 3 == 0 ? "FAILED" : "PAID")")
        }
        if let page = renderTallImage(pageLines) {
            let frameHeight = 600
            var frames: [CGImage] = []
            var signatures: [[[UInt8]?]] = []
            var shifts: [Int] = []
            var top = 0
            while top + frameHeight <= page.height {
                if let frame = page.cropping(to: CGRect(x: 0, y: top, width: page.width, height: frameHeight)) {
                    let rows = ScrollStitching.rowSignatures(frame)
                    if let previous = signatures.last, let shift = ScrollStitcher.offset(previous: previous, next: rows) {
                        shifts.append(shift)
                    }
                    frames.append(frame)
                    signatures.append(rows)
                }
                top += 370
            }
            let stitched = ScrollStitching.stitch(frames: frames, shifts: shifts, signatures: signatures)
            let expected = frameHeight + 370 * (frames.count - 1)
            check(shifts.count == frames.count - 1 && stitched?.height == expected, "Scrolling screenshot stitches frames", "shifts \(shifts) height \(stitched?.height ?? 0) expected \(expected)")
            if let glued = stitched, let original = page.cropping(to: CGRect(x: 0, y: 0, width: page.width, height: expected)), let gluedPixels = ScreenshotComparison.rgba(glued, width: glued.width, height: glued.height), let originalPixels = ScreenshotComparison.rgba(original, width: glued.width, height: glued.height) {
                let difference = PixelDiff.compare(width: glued.width, height: glued.height, first: gluedPixels, second: originalPixels)
                check(difference.changedPixels == 0, "Stitched image equals the page", "\(difference.changedPixels) pixels differ")
            }
        }

        // 12. QR codes: make one, read it back.
        let link = "https://stage.example.com/checkout?id=4521&lang=ru"
        if let qr = QRCode.image(for: link), let qrImage = qr.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let payloads = await QRCode.read(qrImage)
            check(payloads == [link], "QR code round trip", "\(payloads)")
        } else {
            check(false, "QR code renders")
        }

        // Scratch settings leave no file behind. macOS writes an empty file a moment after a domain
        // is removed, so the files go once every check is done and that write has happened.
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        for domain in scratchDomains {
            try? FileManager.default.removeItem(at: preferencesFile(domain))
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        var leftovers: [String] = []
        for domain in scratchDomains where FileManager.default.fileExists(atPath: preferencesFile(domain).path) {
            leftovers.append(domain)
        }
        check(!scratchDomains.isEmpty && leftovers.isEmpty, "self-test leaves no settings files behind", leftovers.joined(separator: ", "))

        print(failures.isEmpty ? "\nALL CHECKS PASSED" : "\n\(failures.count) CHECK(S) FAILED: \(failures.joined(separator: ", "))")
        return failures.isEmpty ? 0 : 1
    }

    /// `variableRate`: bursts of frames with half-second pauses, like the real buffer on a static screen.
    static func writeSyntheticVideo(to url: URL, seconds: Double, size: CGSize, variableRate: Bool = false) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var frameTimes: [Double] = []
        var time = 0.0
        var index = 0
        while time < seconds {
            frameTimes.append(time)
            index += 1
            if variableRate && index % 12 == 0 {
                time += 0.5
            } else {
                time += 1.0 / 30.0
            }
        }
        let frames = frameTimes.count
        for index in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let pixelBuffer = buffer else { continue }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                context.setFillColor(NSColor(hex: 0xF6F7F9).cgColor)
                context.fill(CGRect(origin: .zero, size: size))
                let progress = CGFloat(index) / CGFloat(frames)
                context.setFillColor(NSColor(hex: 0x4C9BFF).cgColor)
                context.fill(CGRect(x: 80 + progress * (size.width - 320), y: 300, width: 160, height: 120))
                let graphics = NSGraphicsContext(cgContext: context, flipped: false)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = graphics
                let label = String(format: "frame %03d · %.2fs", index, Double(index) / 30) as NSString
                label.draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 36, weight: .bold), .foregroundColor: NSColor.black])
                NSGraphicsContext.restoreGraphicsState()
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(seconds: frameTimes[index], preferredTimescale: 600))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw BufferError.exportFailed(writer.error?.localizedDescription ?? "synthetic video")
        }
    }

    private static func writeSineAudio(to url: URL, seconds: Double) throws {
        try? FileManager.default.removeItem(at: url)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frameCount = AVAudioFrameCount(seconds * 48000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        for channel in 0..<2 {
            let samples = buffer.floatChannelData![channel]
            for index in 0..<Int(frameCount) {
                samples[index] = 0.2 * sin(2 * .pi * 440 * Float(index) / 48000)
            }
        }
        try file.write(from: buffer)
    }

    /// A fake checkout page, like the one in the design mockups.
    static func makeSampleScreenshot(size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSColor(hex: 0xF6F7F9).setFill()
        CGRect(origin: .zero, size: size).fill()
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: size.width, height: 90).fill()
        func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ fontSize: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor = NSColor(hex: 0x1C1D20)) {
            (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: weight), .foregroundColor: color])
        }
        text("[Your App]", 48, 30, 26, .bold)
        text("Catalog      Orders      Checkout", 300, 32, 24, .regular, NSColor(hex: 0x5B5F66))
        text("Payment details", 120, 140, 40, .bold)
        for (index, label) in ["Email  test.qa@myapp.com", "Card number  4242 4242 4242 4242"].enumerated() {
            let y = CGFloat(240 + index * 120)
            NSColor.white.setFill()
            let field = NSBezierPath(roundedRect: CGRect(x: 120, y: y + 30, width: 560, height: 70), xRadius: 10, yRadius: 10)
            field.fill()
            NSColor(hex: 0xD6D9DE).setStroke()
            field.stroke()
            text(label, 140, y + 50, 24)
        }
        NSColor.white.setFill()
        NSBezierPath(roundedRect: CGRect(x: 960, y: 140, width: 480, height: 300), xRadius: 14, yRadius: 14).fill()
        text("Order summary", 990, 170, 28, .semibold)
        text("Subtotal                       €49.00", 990, 220, 24)
        text("Discount                     −€98.00", 990, 270, 24)
        text("Total                          €-49.00", 990, 320, 26, .bold)
        NSColor(hex: 0xFDECEA).setFill()
        NSBezierPath(roundedRect: CGRect(x: 120, y: 860, width: 520, height: 70), xRadius: 10, yRadius: 10).fill()
        text("Payment failed: undefined", 145, 880, 26, .regular, NSColor(hex: 0x8A1C0E))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    // MARK: Core speed

    static func perfCore() -> Int32 {
        var failures = 0
        func measure(_ name: String, limit: Double, _ body: () -> Void) {
            let start = CFAbsoluteTimeGetCurrent()
            body()
            let seconds = CFAbsoluteTimeGetCurrent() - start
            let ok = seconds <= limit
            if !ok { failures += 1 }
            print(String(format: "%@  %@: %.3f s (limit %.2f s)", ok ? "PASS" : "FAIL", name, seconds, limit))
        }

        // ~1.8 MB of JSON, like a big API response.
        var items: [String] = []
        for index in 0..<15000 {
            items.append(#"{"id":\#(index),"sku":"SUB-\#(index)","price":49.00,"tags":["a","b"],"owner":{"email":"user\#(index)@myapp.com","active":true},"note":null}"#)
        }
        let json = "[" + items.joined(separator: ",") + "]"
        print("JSON size: \(json.utf8.count / 1024) KB")
        var pretty = ""
        measure("format 1.8 MB JSON", limit: 1.5) {
            pretty = Formatters.formatJSON(json, options: FormatOptions()).output
        }
        measure("minify 1.8 MB JSON", limit: 1.5) {
            var options = FormatOptions()
            options.mode = .minify
            _ = Formatters.formatJSON(json, options: options)
        }
        let visible = String(pretty.prefix(300_000))
        measure("highlight 300 KB of output", limit: 0.6) {
            _ = SyntaxHighlighter.json(visible)
        }
        measure("detect clipboard type of 1.8 MB", limit: 1.5) {
            _ = ContentDetector.detect(json)
        }
        measure("30 time zone searches", limit: 1.5) {
            for query in ["new", "tokyo", "+5:30", "pst", "india", "lon"] {
                for _ in 0..<5 {
                    _ = WorldClock.search(query)
                }
            }
        }
        measure("1000 time parses", limit: 0.5) {
            for index in 0..<1000 {
                _ = TimeConverter.parse(String(1_792_839_492 + index))
                _ = TimeConverter.parse("2026-10-24T10:58:12Z")
            }
        }
        return failures == 0 ? 0 : 1
    }

    // MARK: Export bisect on a real clip

    /// Runs the editor export on `file` with one kind of edit at a time and reports which fails.
    static func exportCheck(file: URL, folder: URL) async -> Int32 {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: file)
        guard let duration = try? await asset.load(.duration).seconds else {
            print("cannot read \(file.path)")
            return 1
        }
        var events: [InputEvent] = []
        let metadata = file.deletingLastPathComponent().appendingPathComponent("capture.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: metadata), let capture = try? decoder.decode(Capture.self, from: data) {
            events = capture.events
        }
        print("clip \(String(format: "%.3f", duration))s, \(events.count) events")
        var variants: [(name: String, project: VideoProject, events: [InputEvent])] = []
        variants.append((name: "no edits", project: VideoProject(duration: duration), events: []))
        var trimmed = VideoProject(duration: duration)
        trimmed.timeline.trim = TimeSpan(start: 0.5, end: duration)
        variants.append((name: "trim", project: trimmed, events: []))
        var slow = VideoProject(duration: duration)
        slow.timeline.speeds = [SpeedEdit(span: TimeSpan(start: duration / 2, end: duration / 2 + 1), factor: 0.5)]
        variants.append((name: "slow motion", project: slow, events: []))
        var cut = VideoProject(duration: duration)
        cut.timeline.cuts = [TimeSpan(start: duration * 0.3, end: duration * 0.45)]
        variants.append((name: "cut", project: cut, events: []))
        var frozen = VideoProject(duration: duration)
        frozen.timeline.freezes = [FreezeEdit(at: duration * 0.6, duration: 2)]
        variants.append((name: "freeze frame", project: frozen, events: []))
        var everything = VideoProject(duration: duration)
        everything.timeline.trim = TimeSpan(start: 0.3, end: duration - 0.2)
        everything.timeline.cuts = [TimeSpan(start: duration * 0.2, end: duration * 0.3)]
        everything.timeline.speeds = [SpeedEdit(span: TimeSpan(start: duration * 0.5, end: duration * 0.7), factor: 0.5)]
        everything.timeline.freezes = [FreezeEdit(at: duration * 0.8, duration: 1.5)]
        everything.overlays = [VideoOverlay(kind: .blur, span: TimeSpan(start: 0, end: duration), start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.4, y: 0.3))]
        variants.append((name: "all edits together", project: everything, events: []))
        var marked = VideoProject(duration: duration)
        marked.overlays = [VideoOverlay(kind: .text, span: TimeSpan(start: 0, end: duration), start: CGPoint(x: 0.05, y: 0.05), end: CGPoint(x: 0.05, y: 0.05), text: "E2E")]
        marked.showBadge = true
        variants.append((name: "overlays + badge", project: marked, events: []))
        variants.append((name: "recorded events", project: VideoProject(duration: duration), events: events))
        var failures = 0
        for (index, variant) in variants.enumerated() {
            do {
                let output = try await VideoCompositor.build(asset: asset, project: variant.project, events: variant.events, environment: EnvironmentSnapshot())
                let url = folder.appendingPathComponent("variant-\(index).mp4")
                try await VideoCompositor.exportMP4(output, quality: .p720, to: url, progress: nil)
                let exported = try await AVURLAsset(url: url).load(.duration).seconds
                print(String(format: "PASS  %@ → %.3fs (expected %.3fs)", variant.name, exported, output.duration))
            } catch {
                failures += 1
                print("FAIL  \(variant.name): \(error)")
                if let output = try? await VideoCompositor.build(asset: asset, project: variant.project, events: variant.events, environment: EnvironmentSnapshot()) {
                    let delegate = ValidationLogger()
                    let range = CMTimeRange(start: .zero, duration: output.composition.duration)
                    let valid = (try? await output.videoComposition.isValid(for: output.composition, timeRange: range, validationDelegate: delegate)) ?? false
                    print("      valid=\(valid) composition=\(output.composition.duration.seconds)s expected=\(output.duration)s")
                    for track in output.composition.tracks(withMediaType: .video) {
                        for segment in track.segments {
                            let target = segment.timeMapping.target
                            let source = segment.timeMapping.source
                            print(String(format: "      segment empty=%@ target %.4f+%.4f source %.4f+%.4f", segment.isEmpty ? "yes" : "no", target.start.seconds, target.duration.seconds, source.start.seconds, source.duration.seconds))
                        }
                    }
                    for line in delegate.lines {
                        print("      " + line)
                    }
                }
            }
        }
        return failures == 0 ? 0 : 1
    }

}

final class ValidationLogger: NSObject, AVVideoCompositionValidationHandling {
    var lines: [String] = []

    func videoComposition(_ videoComposition: AVVideoComposition, shouldContinueValidatingAfterFindingInvalidValueForKey key: String) -> Bool {
        lines.append("invalid value for key \(key)")
        return true
    }

    func videoComposition(_ videoComposition: AVVideoComposition, shouldContinueValidatingAfterFindingEmptyTimeRange timeRange: CMTimeRange) -> Bool {
        lines.append(String(format: "empty time range %.4f+%.4f", timeRange.start.seconds, timeRange.duration.seconds))
        return true
    }

    func videoComposition(_ videoComposition: AVVideoComposition, shouldContinueValidatingAfterFindingInvalidTimeRangeIn videoCompositionInstruction: any AVVideoCompositionInstructionProtocol) -> Bool {
        lines.append(String(format: "invalid instruction range %.4f+%.4f", videoCompositionInstruction.timeRange.start.seconds, videoCompositionInstruction.timeRange.duration.seconds))
        return true
    }

    func videoComposition(_ videoComposition: AVVideoComposition, shouldContinueValidatingAfterFindingInvalidTrackIDIn videoCompositionInstruction: any AVVideoCompositionInstructionProtocol, layerInstruction: AVVideoCompositionLayerInstruction, asset: AVAsset) -> Bool {
        lines.append("invalid track id")
        return true
    }
}
#endif
