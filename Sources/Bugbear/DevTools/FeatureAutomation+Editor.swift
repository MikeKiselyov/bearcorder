// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AVFoundation
import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import SwiftUI
import BugbearCore

@MainActor
extension FeatureAutomation {
    static func runEditor(_ name: String, _ argument: String, _ parts: [String], _ app: AppState) async -> String? {
        switch name {
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
                lines.append("\(title as? String ?? "?")@\(ControlTree.whole(box.minX)),\(ControlTree.whole(box.minY)),\(ControlTree.whole(box.width))x\(ControlTree.whole(box.height)) min=\(minimized as? Bool ?? false)")
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

        case "editor-state":
            // The open screenshot editor: what its buttons change.
            guard let window = NSApp.windows.first(where: { item in (item.identifier?.rawValue ?? "").hasPrefix("screenshot:") && item.isVisible }) else { return "no editor" }
            guard let canvas = FeatureAutomation.findCanvas(in: window.contentView) else { return "no canvas" }
            let document = canvas.document
            let zoom = String(format: "%.2f", document.zoom)
            return "tool=\(document.tool.rawValue) color=\(document.color.name) size=\(document.sizeValue) marks=\(document.annotations.count) undo=\(document.canUndo) redo=\(document.canRedo) zoom=\(zoom) crop=\(document.crop != nil) badge=\(document.showBadge) corner=\(document.badgeCorner.rawValue) format=\(document.exportFormat.rawValue) width=\(document.base.width) filled=\(document.isFilled)"

        case "editor-crop":
            // editor-crop:x,y,w,h as parts of the picture (0-1): crops the open screenshot.
            guard let window = NSApp.windows.first(where: { item in (item.identifier?.rawValue ?? "").hasPrefix("screenshot:") && item.isVisible }),
                  let canvas = FeatureAutomation.findCanvas(in: window.contentView) else { return "no editor" }
            let numbers = argument.split(separator: ",")
            guard numbers.count == 4, let x = Double(numbers[0]), let y = Double(numbers[1]), let width = Double(numbers[2]), let height = Double(numbers[3]) else { return "bad crop" }
            let document = canvas.document
            let pictureWidth = Double(document.base.width)
            let pictureHeight = Double(document.base.height)
            document.setCrop(CGRect(x: x * pictureWidth, y: y * pictureHeight, width: width * pictureWidth, height: height * pictureHeight))
            return "crop=\(document.crop != nil)"

        case "pasteboard-types":
            var names: [String] = []
            for type in NSPasteboard.general.types ?? [] {
                names.append(type.rawValue)
            }
            return names.joined(separator: ",")

        case "close-color-panel":
            NSColorPanel.shared.close()
            return "closed"

        case "open-capture":
            // open-capture:<id>: the capture's editor, as History opens it.
            guard let capture = CaptureStore.shared.captures.first(where: { item in item.id.uuidString == argument }) else { return "no capture" }
            WindowManager.shared.openEditor(for: capture)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            return "opened"

        case "video-state":
            // The open video editor: what its buttons change.
            guard let model = VideoEditorModel.newest else { return "no editor" }
            let timeline = model.project.timeline
            let project = model.project
            let playhead = String(format: "%.1f", model.playhead)
            let trim = String(format: "%.1f-%.1f", timeline.trim.start, timeline.trim.end)
            return "tool=\(model.tool) playhead=\(playhead) playing=\(model.isPlaying) trim=\(trim) cuts=\(timeline.cuts.count) speeds=\(timeline.speeds.count) freezes=\(timeline.freezes.count) overlays=\(project.overlays.count) clicks=\(project.showClicks) keys=\(project.showKeys) steps=\(project.isShowingSteps) badge=\(project.showBadge) format=\(project.format.rawValue) undo=\(model.canUndo) scale=\(project.overlays.last?.effectiveScale ?? 0) clear=\(project.overlays.last?.clearBackground ?? false) lastLength=\(String(format: "%.1f", project.overlays.last?.span.duration ?? 0)) duration=\(String(format: "%.1f", model.duration)) lastBox=\(FeatureAutomation.boxText(project.overlays.last)) lastKind=\(project.overlays.last?.kind.rawValue ?? "none") lastText=\((project.overlays.last?.text ?? "").replacingOccurrences(of: " ", with: "_")) typing=\(model.editingTextID != nil) lastStart=\(String(format: "%.1f", project.overlays.last?.span.start ?? 0)) lastColor=\(String(format: "%06X", project.overlays.last?.color.hex ?? 0)) crop=\(FeatureAutomation.cropText(project.crop)) render=\(Int(model.output?.renderSize.width ?? 0))x\(Int(model.output?.renderSize.height ?? 0)) source=\(Int(model.sourceSize.width))x\(Int(model.sourceSize.height))"

        case "video-range":
            // video-range:<start>,<end> seconds: what dragging on the ruler selects.
            guard let model = VideoEditorModel.newest else { return "no editor" }
            let numbers = argument.split(separator: ",")
            guard numbers.count == 2, let start = Double(numbers[0]), let end = Double(numbers[1]) else { return "bad range" }
            model.range = TimeSpan(start: start, end: end)
            model.seek(toSource: start)
            return "range=\(start)-\(end)"

        case "video-stage":
            // The video frame of the open editor in screen points (top-left), brought to the front,
            // for drawing on it with post-drag.
            guard let model = VideoEditorModel.newest else { return "no editor" }
            guard let window = NSApp.windows.first(where: { item in (item.identifier?.rawValue ?? "").hasPrefix("video:") && item.isVisible }) else { return "no window" }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(nanoseconds: 400_000_000)
            let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
            let video = model.stageVideoRect
            let left = window.frame.minX + video.minX
            let top = mainHeight - window.frame.maxY + video.minY
            return "x=\(Int(left)) y=\(Int(top)) w=\(Int(video.width)) h=\(Int(video.height))"

        case "video-frame-diff":
            // How many pixels inside the last mark's box differ between the preview frame at the
            // playhead (with the marks) and the clip's own frame: 0 means the mark does not show.
            guard let model = VideoEditorModel.newest, let output = model.output, let mark = model.project.overlays.last else { return "no editor, preview or mark" }
            let outputTime = CMTime(seconds: output.timeMap.outputTime(forSource: model.playhead), preferredTimescale: 600)
            let sourceTime = CMTime(seconds: model.playhead, preferredTimescale: 600)
            let edited = AVAssetImageGenerator(asset: output.composition)
            edited.videoComposition = output.videoComposition
            let plain = AVAssetImageGenerator(asset: model.asset)
            for generator in [edited, plain] {
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                generator.maximumSize = CGSize(width: 640, height: 640)
            }
            guard let withMarks = try? await edited.image(at: outputTime).image, let without = try? await plain.image(at: sourceTime).image else { return "no frames" }
            let width = min(withMarks.width, without.width)
            let height = min(withMarks.height, without.height)
            guard let first = ScreenshotComparison.rgba(withMarks, width: width, height: height), let second = ScreenshotComparison.rgba(without, width: width, height: height) else { return "no pixels" }
            var box = mark.rect
            if mark.kind == .text {
                box = VideoOverlay.textBox(mark)
            }
            var changed = 0
            let minX = max(0, Int(box.minX * Double(width)) - 4)
            let maxX = min(width - 1, Int(box.maxX * Double(width)) + 4)
            let minY = max(0, Int(box.minY * Double(height)) - 4)
            let maxY = min(height - 1, Int(box.maxY * Double(height)) + 4)
            if minX <= maxX && minY <= maxY {
                for y in minY...maxY {
                    for x in minX...maxX {
                        let index = (y * width + x) * 4
                        let difference = abs(Int(first[index]) - Int(second[index])) + abs(Int(first[index + 1]) - Int(second[index + 1])) + abs(Int(first[index + 2]) - Int(second[index + 2]))
                        if difference > 60 {
                            changed += 1
                        }
                    }
                }
            }
            return "changed=\(changed) playhead=\(String(format: "%.1f", model.playhead)) span=\(String(format: "%.1f-%.1f", mark.span.start, mark.span.end))"

        case "live-state":
            // The window for drawing on the screen during a recording.
            return app.overlay.stateForChecks

        case "screen-color":
            // screen-color:x,y,w,h[:RRGGBB] (top-left screen points): pixels of the mark color (coral
            // unless given) on the screen there now, Bugbear's own windows included: whether a mark
            // really shows.
            var wanted: UInt32 = 0xFF6B4A
            if parts.count > 2, let given = UInt32(parts[2], radix: 16) {
                wanted = given
            }
            let wantedRed = Int((wanted >> 16) & 0xFF)
            let wantedGreen = Int((wanted >> 8) & 0xFF)
            let wantedBlue = Int(wanted & 0xFF)
            let numbers = argument.split(separator: ",")
            guard numbers.count == 4, let x = Double(numbers[0]), let y = Double(numbers[1]), let width = Double(numbers[2]), let height = Double(numbers[3]) else { return "bad rect" }
            let area = CGRect(x: x, y: y, width: width, height: height)
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return "no screen access" }
            guard let display = content.displays.first(where: { item in item.frame.contains(CGPoint(x: area.midX, y: area.midY)) }) else { return "no display there" }
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(x: area.minX - display.frame.minX, y: area.minY - display.frame.minY, width: area.width, height: area.height)
            configuration.width = Int(area.width)
            configuration.height = Int(area.height)
            configuration.showsCursor = false
            let filter = SCContentFilter(display: display, excludingWindows: [])
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else { return "no picture" }
            guard let pixels = ScreenshotComparison.rgba(image, width: image.width, height: image.height) else { return "no pixels" }
            var matching = 0
            var index = 0
            while index + 3 < pixels.count {
                let red = Int(pixels[index])
                let green = Int(pixels[index + 1])
                let blue = Int(pixels[index + 2])
                if abs(red - wantedRed) < 50 && abs(green - wantedGreen) < 50 && abs(blue - wantedBlue) < 50 {
                    matching += 1
                }
                index += 4
            }
            return "coral=\(matching) of \(image.width * image.height)"


        case "video-seek":
            // video-seek:<seconds|end>: moves the playhead, with no range selected.
            guard let model = VideoEditorModel.newest else { return "no editor" }
            model.range = nil
            var target = Double(argument) ?? 0
            if argument == "end" {
                target = model.project.timeline.trim.end
            }
            model.seek(toSource: target)
            return "playhead=\(String(format: "%.1f", model.playhead))"

        case "video-add-overlay":
            // video-add-overlay:<text|arrow|rectangle|blur>: a mark in the middle, selected.
            guard let model = VideoEditorModel.newest, let kind = VideoOverlay.Kind(rawValue: argument) else { return "no editor or kind" }
            model.addOverlay(kind: kind, start: CGPoint(x: 0.4, y: 0.4), end: CGPoint(x: 0.6, y: 0.6))
            // Text gets words at once, as if typed on the video and finished.
            if kind == .text, let id = model.editingTextID {
                model.setText("Bug here", of: id)
                model.finishTextEditing()
            }
            return "overlays=\(model.project.overlays.count)"

        case "editor-paste-key":
            // editor-paste-key:<canvas|elsewhere>: a picture on the clipboard and a real ⌘V in the
            // open screenshot editor, with the focus on the canvas or somewhere else in the window.
            guard let window = NSApp.windows.first(where: { item in (item.identifier?.rawValue ?? "").hasPrefix("screenshot:") && item.isVisible }) else { return "no editor" }
            guard let canvas = FeatureAutomation.findCanvas(in: window.contentView) else { return "no canvas" }
            let document = canvas.document
            guard let shot = ImageFiles.load(document.capture.mediaURL), let png = ImageFiles.pngData(shot) else { return "no picture" }
            window.makeKeyAndOrderFront(nil)
            // A real click on the title bar brings Bugbear to the front, as a person's click would.
            let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
            let titlePoint = CGPoint(x: window.frame.midX, y: mainHeight - window.frame.maxY + 8)
            let press = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: titlePoint, mouseButton: .left)
            let release = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: titlePoint, mouseButton: .left)
            press?.post(tap: .cghidEventTap)
            release?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 500_000_000)
            if argument == "canvas" {
                window.makeFirstResponder(canvas)
            } else {
                window.makeFirstResponder(nil)
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(png, forType: .png)
            let before = document.annotations.count
            try? await Task.sleep(nanoseconds: 300_000_000)
            // A real key goes to the app in front: never type into someone's chat or document.
            guard FeatureAutomation.frontAppIsBugbear() else {
                pasteboard.clearContents()
                return "not in front: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")"
            }
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true)
            down?.flags = .maskCommand
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 800_000_000)
            let added = document.annotations.count - before
            let isPicture = document.annotations.last?.tool == .image
            if added > 0 {
                document.undo()
            }
            return "added=\(added) picture=\(isPicture) key=\(window.isKeyWindow) active=\(NSApp.isActive)"

        case "editor-checks":
            // In the open screenshot editor: the size buttons follow the tool, the fill buttons change
            // the text being typed right away, and Delete removes the selected mark from anywhere.
            guard let window = NSApp.windows.first(where: { item in (item.identifier?.rawValue ?? "").hasPrefix("screenshot:") && item.isVisible }) else { return "no editor" }
            guard let canvas = FeatureAutomation.findCanvas(in: window.contentView) else { return "no canvas" }
            let document = canvas.document
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            var results: [String] = []
            // A new editor draws at line size 7.
            results.append("defaultLine=\(document.stroke == .thick && Int(document.stroke.width) == 7)")

            document.tool = .text
            let textSize = document.sizeIsText && document.sizeValue == Int(document.textPoints)
            document.tool = .rectangle
            let lineSize = !document.sizeIsText && document.sizeValue == Int(document.stroke.width)
            // With a mark selected the control shows and changes that mark, not the setting for new ones.
            let savedStroke = document.stroke
            document.stroke = .heavy
            let thick = Annotation(tool: .rectangle, start: CGPoint(x: 30, y: 30), end: CGPoint(x: 90, y: 90), color: .coral, lineWidth: document.lineWidth)
            document.add(thick)
            document.stroke = .thin
            document.tool = .select
            document.selectedId = thick.id
            let showsSelected = document.sizeValue == Int(StrokeSize.heavy.width)
            document.changeSize(by: 1)
            let grewSelected = (document.annotations.first(where: { item in item.id == thick.id })?.lineWidth ?? 0) > thick.lineWidth
            document.delete(thick.id)
            document.stroke = savedStroke
            results.append("sizeFollowsTool=\(textSize && lineSize)")
            results.append("sizeFollowsSelection=\(showsSelected && grewSelected)")

            let savedClear = document.clearTextBackground
            document.tool = .text
            document.clearTextBackground = false
            canvas.startTypingForChecks(at: CGPoint(x: 80, y: 80))
            try? await Task.sleep(nanoseconds: 300_000_000)
            let typedID = document.editingTextId
            let labelAtStart = document.annotations.first(where: { item in item.id == typedID })?.hasClearBackground == false
            document.setFilled(false)
            try? await Task.sleep(nanoseconds: 400_000_000)
            let clearAfterNoFill = document.annotations.first(where: { item in item.id == typedID })?.hasClearBackground == true
            // The field shows only the caret, so the text is never drawn twice.
            let fieldIsClear = canvas.typingFieldDrawsText == false
            results.append("typingNoFillAtOnce=\(labelAtStart && clearAfterNoFill)")
            results.append("textDrawnOnce=\(fieldIsClear)")
            window.makeFirstResponder(nil)
            document.clearTextBackground = savedClear

            // Arrow with text: the note opens for typing as soon as the arrow is drawn; left empty,
            // a plain arrow stays.
            let toolBefore = document.tool
            document.tool = .callout
            canvas.drawForChecks(from: CGPoint(x: 140, y: 140), to: CGPoint(x: 260, y: 200))
            try? await Task.sleep(nanoseconds: 300_000_000)
            let noteID = document.editingTextId
            let typingAtOnce = noteID != nil && document.annotations.first(where: { item in item.id == noteID })?.tool == .callout
            canvas.finishTypingForChecks("Wrong total")
            let keptNote = document.annotations.first(where: { item in item.id == noteID })
            let noteSaved = keptNote?.tool == .callout && keptNote?.text == "Wrong total"
            canvas.drawForChecks(from: CGPoint(x: 140, y: 260), to: CGPoint(x: 260, y: 320))
            try? await Task.sleep(nanoseconds: 300_000_000)
            let emptyID = document.editingTextId
            canvas.finishTypingForChecks("")
            let leftEmpty = document.annotations.first(where: { item in item.id == emptyID })
            let becameArrow = emptyID != nil && leftEmpty?.tool == .arrow
            results.append("calloutTyping=\(typingAtOnce && noteSaved)")
            results.append("calloutEmptyIsArrow=\(becameArrow)")
            if let id = noteID {
                document.delete(id)
            }
            if let id = emptyID {
                document.delete(id)
            }
            document.tool = toolBefore

            // ⌘V with a picture on the clipboard places it on the screenshot, selected.
            if let shot = ImageFiles.load(document.capture.mediaURL), let png = ImageFiles.pngData(shot) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setData(png, forType: .png)
                let pasted = canvas.pasteImage()
                let placed = document.annotations.last
                let fileSaved = placed?.imagePath.map { path in FileManager.default.fileExists(atPath: path) } ?? false
                results.append("pasteImage=\(pasted && placed?.tool == .image && fileSaved && document.selectedId == placed?.id)")
                if let id = placed?.id, placed?.tool == .image {
                    document.delete(id)
                }
            }

            // Delete in the editor window with the focus away from the canvas: the window's key handling,
            // not delivery from the keyboard (the key is posted into Bugbear's own event queue).
            let box = Annotation(tool: .rectangle, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 60, y: 60), color: .coral, lineWidth: 4)
            document.add(box)
            document.tool = .select
            document.selectedId = box.id
            window.makeFirstResponder(nil)
            // Let the typing field from the step above give up the focus first; while a field types,
            // Delete belongs to it.
            try? await Task.sleep(nanoseconds: 400_000_000)
            // The key is sent to Bugbear itself, never to whatever app is in front (the browser the
            // features test opened can take the focus at any moment).
            // It goes into Bugbear's own event queue for the editor window, so it takes the same way as
            // a real key press (the window's key monitor included).
            window.makeKeyAndOrderFront(nil)
            for type in [NSEvent.EventType.keyDown, NSEvent.EventType.keyUp] {
                if let key = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}", isARepeat: false, keyCode: 51) {
                    NSApp.postEvent(key, atStart: false)
                }
            }
            var deleted = false
            for _ in 0..<15 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if !document.annotations.contains(where: { item in item.id == box.id }) {
                    deleted = true
                    break
                }
            }
            results.append("deleteInEditorWindow=\(deleted)")
            return results.joined(separator: " ")

        case "tooltip-probe":
            // tooltip-probe:<window id prefix|menubar>,<x>,<y>: points at x,y (from the window's
            // top-left), waits, and reports how many Bugbear tooltips are on screen.
            let parts = argument.split(separator: ",")
            guard parts.count == 3, let offsetX = Double(parts[1]), let offsetY = Double(parts[2]) else { return "bad argument" }
            // "menubar" is the panel under the bear; it is checked without making the app active.
            let isMenuPanel = parts[0] == "menubar"
            var found: NSWindow?
            for item in NSApp.windows where item.isVisible {
                if isMenuPanel && item.className.contains("MenuBarExtra") {
                    found = item
                }
                if !isMenuPanel && (item.identifier?.rawValue ?? "").hasPrefix(String(parts[0])) {
                    found = item
                }
            }
            guard let window = found else { return "no window" }
            if isMenuPanel {
                // The way it is used: another app in front, Bugbear not active.
                NSApp.deactivate()
                try? await Task.sleep(nanoseconds: 300_000_000)
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            HoverTip.shared.hide()
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let point = CGPoint(x: window.frame.minX + offsetX, y: primaryHeight - window.frame.maxY + offsetY)
            let source = CGEventSource(stateID: .hidSystemState)
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: point.x - 30, y: point.y), mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 300_000_000)
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            var tooltips = 0
            for item in NSApp.windows where item.isVisible && item is HoverTipPanel {
                tooltips += 1
            }
            return "key=\(window.isKeyWindow) active=\(NSApp.isActive) tooltips=\(tooltips)"

        default:
            return nil
        }
    }
}
#endif
