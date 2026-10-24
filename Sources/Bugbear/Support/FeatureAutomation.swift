import AVFoundation
import AppKit
import BugbearCore

/// Automation commands for scripts/e2e-features.sh: drive each feature the way a user would,
/// without the pickers and dialogs that need a mouse. Only active with the automation hook on.
@MainActor
enum FeatureAutomation {
    /// Handles `command` if it is a feature command. Returns the result text, or nil for unknown commands.
    static func run(_ parts: [String]) async -> String? {
        let app = AppState.shared
        let name = parts.first ?? ""
        let argument = parts.count > 1 ? parts[1] : ""
        switch name {
        case "ax":
            return "trusted=\(AXIsProcessTrusted())"

        case "screen":
            let frame = NSScreen.main?.frame ?? .zero
            return "width=\(Int(frame.width)) height=\(Int(frame.height)) front=\(app.lastExternalApp?.localizedName ?? "?")"

        case "move-front":
            // move-front:x,y (top-left, points)
            let numbers = argument.split(separator: ",")
            guard numbers.count == 2, let x = Double(numbers[0]), let y = Double(numbers[1]) else { return "bad point" }
            return "moved=\(WindowResizer.move(app: app.lastExternalApp, to: CGPoint(x: x, y: y)))"

        case "web-area":
            // The visible page area of the front browser window: normalized on the display it is on
            // (top-left origin), then its global top-left frame in points, then that display's width.
            // The scroll test does not depend on toolbars, tab bars or which display holds the window.
            guard let running = app.lastExternalApp, let frame = webAreaFrame(of: running), let primary = NSScreen.screens.first else { return "no web area" }
            let center = CGPoint(x: frame.midX, y: primary.frame.maxY - frame.midY)
            guard let screen = NSScreen.screens.first(where: { item in item.frame.contains(center) }) else { return "no screen" }
            let screenTop = primary.frame.maxY - screen.frame.maxY
            let x = (frame.minX - screen.frame.minX) / screen.frame.width
            let y = (frame.minY - screenTop) / screen.frame.height
            let width = frame.width / screen.frame.width
            let height = frame.height / screen.frame.height
            return String(format: "%.4f,%.4f,%.4f,%.4f %d,%d,%d,%d %d", x, y, width, height, Int(frame.minX), Int(frame.minY), Int(frame.width), Int(frame.height), Int(screen.frame.width))

        case "scroll-capture":
            // scroll-capture:x,y,w,h (normalized area on the screen under the pointer)
            guard let area = selection(argument) else { return "bad area" }
            do {
                guard let image = try await ScrollingCapture.shared.run(on: area.screen, area: area) else { return "cancelled" }
                let file = AppPaths.temporary.appendingPathComponent("e2e-scroll.png")
                ImageFiles.write(image, to: file, type: "public.png")
                return "width=\(image.width) height=\(image.height) file=\(file.path)"
            } catch {
                return "error \(error)"
            }

        case "scroll-probe":
            // scroll-probe:x,y,w,h:<points>
            guard let area = selection(argument) else { return "bad area" }
            let points = parts.count > 2 ? Int(parts[2]) ?? 300 : 300
            do {
                return try await ScrollingCapture.shared.probe(on: area.screen, area: area, points: points)
            } catch {
                return "error \(error)"
            }

        case "stitch-files":
            // stitch-files:<a.png>:<b.png> → best shift and the score at a few shifts
            guard parts.count > 2, let first = ImageFiles.load(URL(fileURLWithPath: argument)), let second = ImageFiles.load(URL(fileURLWithPath: parts[2])) else { return "no images" }
            let a = ScrollingCapture.rowSignatures(first)
            let b = ScrollingCapture.rowSignatures(second)
            let best = ScrollStitcher.bestShift(previous: a, next: b)
            var flatA = 0
            for row in a where row == nil { flatA += 1 }
            return "rows=\(a.count) flat=\(flatA) best=\(best.shift ?? -1)@err\(String(format: "%.1f", best.error)) next=\(String(format: "%.1f", best.runnerUp))/\(best.compared) diag=\(ScrollStitcher.diagnose(previous: a, next: b, shift: 488))"

        case "ocr-file":
            // ocr-file:<path> → the recognized text, lines joined with " | "
            // Tall images are read in 1000 px pieces with 150 px overlap: Vision shrinks huge images.
            guard let image = ImageFiles.load(URL(fileURLWithPath: argument)) else { return "no image" }
            var texts: [String] = []
            var top = 0
            while top < image.height {
                let height = min(1000, image.height - top)
                if let piece = image.cropping(to: CGRect(x: 0, y: top, width: image.width, height: height)) {
                    let lines = (try? await TextRecognizer.recognize(piece)) ?? []
                    texts.append(TextRecognizer.text(of: lines).replacingOccurrences(of: "\n", with: " | "))
                }
                if top + height >= image.height { break }
                top += 850
            }
            return texts.joined(separator: " || ")

        case "clip-screens":
            // The screens of the newest capture: id=name(clicks) and which one is selected.
            guard let clip = app.store.captures.first else { return "no capture" }
            guard let screens = clip.screens else { return "single screen" }
            var parts: [String] = []
            for screen in screens {
                let exists = FileManager.default.fileExists(atPath: clip.folder.appendingPathComponent(screen.file).path)
                parts.append("\(screen.id)=\(screen.name)(clicks:\(screen.events.filter { event in event.kind == .click }.count) file:\(exists))")
            }
            return "selected=\(clip.selectedScreen ?? "?") " + parts.joined(separator: " ")

        case "select-screen":
            // select-screen:<id> on the newest capture; prints the picture size afterwards.
            guard let clip = app.store.captures.first else { return "no capture" }
            let started = Date()
            do {
                let updated = try await app.store.selectScreen(argument, of: clip, framesPerSecond: app.settings.framesPerSecond)
                if updated.kind == .screenshot {
                    guard let image = ImageFiles.load(updated.mediaURL) else { return "no image" }
                    let marks = FileManager.default.fileExists(atPath: updated.projectURL.path)
                    return "selected=\(updated.selectedScreen ?? "?") size=\(image.width)x\(image.height) project=\(marks)"
                }
                guard let track = try await AVURLAsset(url: updated.mediaURL).loadTracks(withMediaType: .video).first else { return "no track" }
                let size = try await track.load(.naturalSize)
                return String(format: "selected=%@ size=%dx%d duration=%.2f took=%.2fs", updated.selectedScreen ?? "?", Int(size.width), Int(size.height), updated.duration, Date().timeIntervalSince(started))
            } catch {
                let details = error as NSError
                return "error \(details.domain) \(details.code) \(details.userInfo)"
            }

        case "front-title":
            // The title of the front app's focused window, so scripts act only on their own window.
            guard let running = app.lastExternalApp else { return "title=" }
            let element = AXUIElementCreateApplication(running.processIdentifier)
            var focused: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &focused) == .success, let window = focused, CFGetTypeID(window) == AXUIElementGetTypeID() else { return "title=" }
            var title: AnyObject?
            AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title)
            return "title=\(title as? String ?? "")"

        case "app-windows":
            // app-windows:<name>: the app's windows from Accessibility: title, top-left, size, minimized.
            guard let running = NSWorkspace.shared.runningApplications.first(where: { item in item.localizedName == argument }) else { return "not running" }
            let element = AXUIElementCreateApplication(running.processIdentifier)
            var value: AnyObject?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success, let windows = value as? [AXUIElement] else { return "no windows" }
            var lines: [String] = []
            for window in windows {
                var title: AnyObject?
                var minimized: AnyObject?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
                AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
                let box = frame(of: window) ?? .zero
                lines.append("\(title as? String ?? "?")@\(Int(box.minX)),\(Int(box.minY)),\(Int(box.width))x\(Int(box.height)) min=\(minimized as? Bool ?? false)")
            }
            return "\(windows.count): " + lines.joined(separator: " | ")

        case "activate-app":
            // activate-app:<name>: clicks the title bar of the app's frontmost window, the way a person
            // would. `open -a` no longer brings an app forward when another app has the focus.
            guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return "no windows" }
            for info in list {
                guard let owner = info[kCGWindowOwnerName as String] as? String, owner == argument else { continue }
                guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
                guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat], let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"], width > 200 else { continue }
                let point = CGPoint(x: x + width / 2, y: y + 12)
                let source = CGEventSource(stateID: .hidSystemState)
                CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 120_000_000)
                CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 60_000_000)
                CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                try? await Task.sleep(nanoseconds: 500_000_000)
                return "front=\(app.lastExternalApp?.localizedName ?? "?")"
            }
            return "no window of \(argument)"

        case "move-pointer":
            // move-pointer:x,y (top-left screen points), e.g. onto the second display.
            let numbers = argument.split(separator: ",")
            guard numbers.count == 2, let x = Double(numbers[0]), let y = Double(numbers[1]) else { return "bad point" }
            let source = CGEventSource(stateID: .hidSystemState)
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 200_000_000)
            return "pointer \(Int(x)),\(Int(y))"

        case "screens":
            // Every display: AppKit frame, scale, and which one holds the pointer.
            var lines: [String] = []
            let mouse = NSEvent.mouseLocation
            for screen in NSScreen.screens {
                let frame = screen.frame
                let pointer = frame.contains(mouse) ? " pointer" : ""
                lines.append("\(AppState.displayID(of: screen)):\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))x\(Int(frame.height))@\(screen.backingScaleFactor)\(pointer)")
            }
            return lines.joined(separator: ";")

        case "post-click":
            // post-click:x,y (top-left screen points): a real left click.
            let numbers = argument.split(separator: ",")
            guard numbers.count == 2, let x = Double(numbers[0]), let y = Double(numbers[1]) else { return "bad point" }
            let point = CGPoint(x: x, y: y)
            let source = CGEventSource(stateID: .hidSystemState)
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 120_000_000)
            CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 60_000_000)
            CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            return "clicked \(Int(x)),\(Int(y))"

        case "post-drag":
            // post-drag:x1,y1:x2,y2 (top-left screen points): press, move in steps, release.
            let from = argument.split(separator: ",")
            let to = (parts.count > 2 ? parts[2] : "").split(separator: ",")
            guard from.count == 2, to.count == 2, let x1 = Double(from[0]), let y1 = Double(from[1]), let x2 = Double(to[0]), let y2 = Double(to[1]) else { return "bad points" }
            let source = CGEventSource(stateID: .hidSystemState)
            let start = CGPoint(x: x1, y: y1)
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 100_000_000)
            CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
            for step in 1...10 {
                let progress = Double(step) / 10
                let point = CGPoint(x: x1 + (x2 - x1) * progress, y: y1 + (y2 - y1) * progress)
                try? await Task.sleep(nanoseconds: 30_000_000)
                CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            }
            CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: CGPoint(x: x2, y: y2), mouseButton: .left)?.post(tap: .cghidEventTap)
            return "dragged"

        case "record-area-picker":
            // Opens the real area picker; the script then clicks and presses Return.
            Task { await app.startRecording(target: .area) }
            return "opening"
        case "picker-chips":
            var texts: [String] = []
            for chip in app.regionSelector.chipCenters {
                texts.append("\(chip.title)@\(Int(chip.point.x)),\(Int(chip.point.y))")
            }
            return texts.joined(separator: ";")
        case "recording-region":
            guard let region = app.recordingRegion else { return "none recording=\(app.recording != nil)" }
            return "region=\(Int(region.global.width))x\(Int(region.global.height)) recording=\(app.recording != nil) outline=\(app.recordingOutline.windowCount)"

        case "frame-of-latest":
            // frame-of-latest:<seconds>:<png path> from the newest video
            guard let clip = app.store.captures.first(where: { item in item.kind == .video }), parts.count > 2 else { return "no video" }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip.mediaURL))
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let seconds = Double(argument) ?? 1
            guard let frame = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image else { return "no frame" }
            ImageFiles.write(frame, to: URL(fileURLWithPath: parts[2]), type: "public.png")
            return "frame=\(frame.width)x\(frame.height)"

        case "pick-color-test":
            // Opens the system color loupe; the script clicks somewhere to pick.
            guard let color = await ColorPick.pick() else { return "cancelled" }
            return "hex=\(ColorConverter.formats(color).hex)"

        case "resize-front":
            // resize-front:1280x720
            let numbers = argument.split(separator: "x")
            guard numbers.count == 2, let width = Double(numbers[0]), let height = Double(numbers[1]) else { return "bad size" }
            let result = WindowResizer.resize(app: app.lastExternalApp, to: CGSize(width: width, height: height))
            switch result {
            case .success(let size):
                return "app=\(app.lastExternalApp?.localizedName ?? "?") size=\(Int(size.width))x\(Int(size.height))"
            case .failure(let failure):
                return "error \(failure)"
            }

        case "ruler-start":
            app.startRuler()
            return "active=\(ScreenRuler.shared.isActive)"
        case "ruler-stop":
            ScreenRuler.shared.stop()
            return "active=\(ScreenRuler.shared.isActive)"
        case "ruler-state":
            return "active=\(ScreenRuler.shared.isActive)"

        case "overlay-test":
            // overlay-test:<pixels per point>; a 1400×800 px test design.
            let image = NSImage(size: CGSize(width: 1400, height: 800), flipped: false) { rect in
                NSColor(hex: 0x4C9BFF).setFill()
                rect.fill()
                NSColor.white.setFill()
                CGRect(x: 100, y: 100, width: 600, height: 300).fill()
                return true
            }
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return "no image" }
            let design = NSImage(size: CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
            design.addRepresentation(bitmap)
            DesignOverlay.shared.show(design)
            DesignOverlay.shared.scale = Double(argument) ?? 2
            DesignOverlay.shared.opacity = 0.4
            return "open=\(DesignOverlay.shared.isOpen) \(DesignOverlay.shared.debugFrame)"
        case "overlay-click-through":
            DesignOverlay.shared.clickThrough = argument == "true"
            return DesignOverlay.shared.debugFrame
        case "overlay-close":
            DesignOverlay.shared.close()
            return "open=\(DesignOverlay.shared.isOpen)"

        case "fields":
            // fields:Stand=stage-3,Build=1.42  (empty clears)
            var fields: [EnvironmentSnapshot.Field] = []
            for pair in argument.split(separator: ",") {
                let pieces = pair.split(separator: "=", maxSplits: 1)
                if pieces.count == 2 {
                    fields.append(EnvironmentSnapshot.Field(name: String(pieces[0]), value: String(pieces[1])))
                }
            }
            app.settings.reportFields = fields
            return "fields=\(fields.count)"

        case "report":
            // report:markdown|jira, for the newest capture; the text goes to the clipboard.
            guard let latest = app.store.captures.first else { return "no capture" }
            var format = BugReport.Format.markdown
            if argument == "jira" {
                format = .jira
            }
            BugReportBuilder.copy(for: latest, timeMap: nil, files: [latest.mediaURL], format: format)
            return "copied format=\(format.rawValue) default=\(app.settings.bugReportFormat)"

        case "extras-latest":
            guard let latest = app.store.captures.first else { return "no capture" }
            var texts: [String] = []
            for field in latest.environment.extras ?? [] {
                texts.append("\(field.name)=\(field.value)")
            }
            return "extras=\(texts.joined(separator: ","))"

        case "guide-latest":
            // guide-latest:<count>:<folder>
            let count = Int(argument) ?? 2
            let folder = parts.count > 2 ? parts[2] : AppPaths.temporary.path
            var shots: [Capture] = []
            for capture in app.store.captures where capture.kind == .screenshot && shots.count < count {
                shots.append(capture)
            }
            if shots.count < count { return "only \(shots.count) screenshots" }
            WindowManager.shared.openStepGuide(captures: shots)
            let model = StepGuideModel(captures: shots)
            model.steps[0].caption = "Open the page"
            var blocks: [(image: CGImage, caption: String)] = []
            for step in model.steps {
                blocks.append((image: step.image, caption: step.caption))
            }
            let png = URL(fileURLWithPath: folder).appendingPathComponent("guide.png")
            let pdf = URL(fileURLWithPath: folder).appendingPathComponent("guide.pdf")
            guard let image = StepGuideRenderer.longImage(title: "E2E guide", steps: blocks) else { return "no image" }
            ImageFiles.write(image, to: png, type: "public.png")
            let wrote = StepGuideRenderer.writePDF(title: "E2E guide", steps: blocks, to: pdf)
            let pages = CGPDFDocument(pdf as CFURL)?.numberOfPages ?? 0
            return "steps=\(model.steps.count) png=\(image.width)x\(image.height) pdf=\(wrote) pages=\(pages)"

        case "compare-latest":
            var shots: [Capture] = []
            for capture in app.store.captures where capture.kind == .screenshot && shots.count < 2 {
                shots.append(capture)
            }
            if shots.count < 2 { return "need 2 screenshots" }
            WindowManager.shared.openCompare(shots[0], shots[1])
            guard let output = ScreenshotComparison.make(before: shots[1], after: shots[0]) else { return "no comparison" }
            return "regions=\(output.result.regions.count) changed=\(String(format: "%.3f", output.result.changedShare))"

        case "hotkey-set":
            // hotkey-set:<action>:<keyCode>:<cmd,shift,option,control>
            guard let action = HotKeyAction(rawValue: argument), parts.count > 3, let keyCode = UInt32(parts[2]) else { return "bad hotkey" }
            let shortcut = Shortcut(keyCode: keyCode, modifiers: carbonModifiers(parts[3]), key: "?")
            if let owner = HotKeySettings.shared.owner(of: shortcut, except: action) {
                return "conflict with \(owner.rawValue)"
            }
            HotKeySettings.shared.set(shortcut, for: action)
            return "set \(action.rawValue)=\(HotKeySettings.shared.text(for: action))"
        case "hotkey-reset":
            HotKeySettings.shared.resetAll()
            return "customized=\(HotKeySettings.shared.isCustomized)"
        case "post-key":
            // post-key:<keyCode>:<modifiers>: a real key press through the HID event tap.
            guard let keyCode = CGKeyCode(argument), parts.count > 2 else { return "bad key" }
            let flags = cgFlags(parts[2])
            let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
            down?.flags = flags
            let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
            up?.flags = flags
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            return "posted"

        case "record-area":
            // record-area:x,y,w,h
            guard let area = selection(argument) else { return "bad area" }
            await app.startRecording(target: .area, presetRegion: area)
            return "recording=\(app.recording != nil) outline=\(app.recordingOutline.windowCount) region=\(Int(area.global.width))x\(Int(area.global.height))"

        case "cleanup-dryrun":
            // cleanup-dryrun:<days>:<GB>: what the limits would delete, without deleting.
            let days = Int(argument) ?? 0
            let gigabytes = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
            let sizes = await app.store.measureSizes()
            var items: [StoragePolicy.Item] = []
            var total: Int64 = 0
            for capture in app.store.captures {
                let bytes = sizes[capture.id] ?? 0
                total += bytes
                items.append(StoragePolicy.Item(id: capture.id, createdAt: capture.createdAt, bytes: bytes))
            }
            let doomed = StoragePolicy.itemsToDelete(items, now: Date(), maxAgeDays: days, maxBytes: Int64(gigabytes) * 1_000_000_000, protected: [])
            return "captures=\(items.count) total=\(total) wouldDelete=\(doomed.count)"

        case "video-size-test":
            guard let clip = app.store.captures.first(where: { item in item.kind == .video }) else { return "no video" }
            let model = VideoEditorModel(capture: clip)
            model.addOverlay(kind: .arrow, start: CGPoint(x: 0.2, y: 0.2), end: CGPoint(x: 0.5, y: 0.5))
            var steps: [String] = []
            steps.append("\(Int((model.selectedOverlay?.effectiveScale ?? 0) * 100))")
            model.changeSelectedOverlaySize(by: 1)
            model.changeSelectedOverlaySize(by: 1)
            steps.append("\(Int((model.selectedOverlay?.effectiveScale ?? 0) * 100))")
            for _ in 0..<12 {
                model.changeSelectedOverlaySize(by: 1)
            }
            steps.append("\(Int((model.selectedOverlay?.effectiveScale ?? 0) * 100))")
            model.addOverlay(kind: .text, start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.1, y: 0.1))
            let newMarkScale = Int((model.selectedOverlay?.effectiveScale ?? 0) * 100)
            model.deleteSelection()
            model.tearDown()
            return "arrow % \(steps.joined(separator: "→")) newMark=\(newMarkScale)"

        case "editor-size-test":
            return editorSizeTest()

        default:
            return nil
        }
    }

    /// Normalized "x,y,w,h" on the screen under the pointer.
    private static func selection(_ text: String) -> RegionSelector.Selection? {
        var numbers: [CGFloat] = []
        for piece in text.split(separator: ",") {
            guard let value = Double(piece) else { return nil }
            numbers.append(CGFloat(value))
        }
        guard numbers.count == 4 else { return nil }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { item in item.frame.contains(mouse) }) ?? NSScreen.main else { return nil }
        let normalized = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        let frame = screen.frame
        let global = CGRect(x: frame.minX + normalized.minX * frame.width, y: frame.maxY - normalized.maxY * frame.height, width: normalized.width * frame.width, height: normalized.height * frame.height)
        return RegionSelector.Selection(screen: screen, normalized: normalized, global: global)
    }

    /// Visible frame of the first AXWebArea in the app's focused window, in top-left screen points. The web
    /// area itself spans the whole page, so it is cut to the scroll area around it.
    private static func webAreaFrame(of running: NSRunningApplication) -> CGRect? {
        let application = AXUIElementCreateApplication(running.processIdentifier)
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focused) == .success, let window = focused, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var queue: [(element: AXUIElement, parent: AXUIElement?)] = [(element: window as! AXUIElement, parent: nil)]
        var visited = 0
        while !queue.isEmpty && visited < 400 {
            let item = queue.removeFirst()
            visited += 1
            var role: AnyObject?
            AXUIElementCopyAttributeValue(item.element, kAXRoleAttribute as CFString, &role)
            if let roleName = role as? String, roleName == "AXWebArea" {
                guard let page = frame(of: item.element) else { return nil }
                guard let parent = item.parent, let visible = frame(of: parent) else { return page }
                return page.intersection(visible)
            }
            var children: AnyObject?
            if AXUIElementCopyAttributeValue(item.element, kAXChildrenAttribute as CFString, &children) == .success, let list = children as? [AXUIElement] {
                for child in list {
                    queue.append((element: child, parent: item.element))
                }
            }
        }
        return nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionFound = positionValue, let sizeFound = sizeValue else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionFound as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeFound as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    private static func carbonModifiers(_ text: String) -> UInt32 {
        var flags: UInt32 = 0
        if text.contains("cmd") { flags |= 256 }       // cmdKey
        if text.contains("shift") { flags |= 512 }     // shiftKey
        if text.contains("option") { flags |= 2048 }   // optionKey
        if text.contains("control") { flags |= 4096 }  // controlKey
        return flags
    }

    private static func cgFlags(_ text: String) -> CGEventFlags {
        var flags: CGEventFlags = []
        if text.contains("cmd") { flags.insert(.maskCommand) }
        if text.contains("shift") { flags.insert(.maskShift) }
        if text.contains("option") { flags.insert(.maskAlternate) }
        if text.contains("control") { flags.insert(.maskControl) }
        return flags
    }

    /// + and - on a test screenshot and video, the way the editors do it.
    private static func editorSizeTest() -> String {
        guard let shot = CaptureStore.shared.captures.first(where: { item in item.kind == .screenshot }), let document = ScreenshotDocument(capture: shot) else { return "no screenshot" }
        var results: [String] = []
        let arrow = Annotation(tool: .arrow, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 200, y: 200), color: .yellow, lineWidth: document.lineWidth)
        document.annotations.append(arrow)
        document.selectedId = arrow.id
        let widthBefore = document.selected?.lineWidth ?? 0
        document.changeSize(by: 1)
        let widthAfter = document.selected?.lineWidth ?? 0
        results.append("arrowWidth=\(Int(widthBefore))->\(Int(widthAfter)) color=\(document.selected?.color.rawValue ?? "?")")
        var text = Annotation(tool: .text, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 50, y: 50), color: .coral, lineWidth: document.lineWidth)
        text.fontSize = document.fontSize
        text.text = "E2E"
        document.annotations.append(text)
        document.selectedId = text.id
        let fontBefore = document.selected?.fontSize ?? 0
        document.changeSize(by: 1)
        document.changeSize(by: 1)
        let fontAfter = document.selected?.fontSize ?? 0
        results.append("textFont=\(Int(fontBefore))->\(Int(fontAfter))")
        // Leave the test screenshot as it was.
        document.undo()
        document.undo()
        document.annotations.removeAll { item in item.id == arrow.id || item.id == text.id }
        document.saveProject()
        return results.joined(separator: " ")
    }
}
