// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AVFoundation
import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import SwiftUI
import AppCore

@MainActor
extension FeatureAutomation {
    static func runInput(_ name: String, _ argument: String, _ parts: [String], _ app: AppState) async -> String? {
        switch name {
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
        case "picker-selection":
            // The open picker's area: x,y,width,height in top-left screen points.
            guard let rect = app.regionSelector.selectionOnScreen else { return "none" }
            return "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
        case "picker-grip":
            // The grip above the picker's area that moves it, top-left screen points.
            guard let center = app.regionSelector.gripCenterOnScreen else { return "" }
            return "\(Int(center.x)),\(Int(center.y))"
        case "area-grip":
            // The grip above the recording frame that moves the area, top-left screen points.
            guard let center = app.recordingOutline.gripCenter else { return "" }
            return "\(Int(center.x)),\(Int(center.y))"
        case "front-app":
            return NSWorkspace.shared.frontmostApplication?.localizedName ?? "none"
        case "area-handles":
            // Handles on the recording frame, top-left screen points: bottom-left, bottom-right,
            // top-left, top-right, then the left, right, bottom and top edges.
            var texts: [String] = []
            for center in app.recordingOutline.handleCenters {
                texts.append("\(Int(center.x)),\(Int(center.y))")
            }
            return texts.joined(separator: ";")
        case "recording-region":
            guard let region = app.recordingRegion else { return "none recording=\(app.recording != nil)" }
            // at= is the area's top-left corner in top-left screen points.
            let top = (NSScreen.screens.first?.frame.maxY ?? 0) - region.global.maxY
            return "region=\(Int(region.global.width))x\(Int(region.global.height)) recording=\(app.recording != nil) outline=\(app.recordingOutline.windowCount) at=\(Int(region.global.minX)),\(Int(top))"

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

        case "png-black":
            // png-black:<png path>: the share of pure black pixels (nothing recorded there) in the
            // left, right, top and bottom halves, in percent.
            guard let image = ImageFiles.load(URL(fileURLWithPath: argument)), let pixels = ScreenshotComparison.rgba(image, width: image.width, height: image.height) else { return "no picture" }
            var black = [0, 0, 0, 0]
            var total = [0, 0, 0, 0]
            for row in 0..<image.height {
                for column in 0..<image.width {
                    let index = (row * image.width + column) * 4
                    let isBlack = pixels[index] < 3 && pixels[index + 1] < 3 && pixels[index + 2] < 3
                    var halves = [column < image.width / 2 ? 0 : 1]
                    halves.append(row < image.height / 2 ? 2 : 3)
                    for half in halves {
                        total[half] += 1
                        if isBlack {
                            black[half] += 1
                        }
                    }
                }
            }
            var shares: [Int] = []
            for half in 0..<4 {
                shares.append(total[half] == 0 ? 100 : black[half] * 100 / total[half])
            }
            return "left=\(shares[0]) right=\(shares[1]) top=\(shares[2]) bottom=\(shares[3])"

        case "picker-screens":
            // The screens the open area picker covers, the first where it opened, top-left screen
            // points with their scale: x,y,w,h@scale;...
            var texts: [String] = []
            for screen in app.regionSelector.screensOnScreen {
                let rect = screen.rect
                texts.append("\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))@\(Int(screen.scale))")
            }
            return texts.joined(separator: ";")

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

        case "screen-tools":
            // What is open on the screen: drawing, ruler, color loupe, recording.
            return "drawing=\(app.overlay.isDrawing) ruler=\(ScreenRuler.shared.isActive) picking=\(ColorPick.isPicking) recording=\(app.recording != nil) paused=\(app.recording?.isPaused ?? false) target=\(app.recordingTarget) liveTool=\(app.overlay.tool.rawValue) liveColor=\(app.overlay.color.rawValue) fade=\(app.overlay.autoFade)"

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
        case "overlay-state":
            return DesignOverlay.shared.debugFrame
        case "overlay-close":
            DesignOverlay.shared.close()
            return "open=\(DesignOverlay.shared.isOpen)"

        case "fields-count":
            return "fields=\(app.settings.reportFields.count)"

        default:
            return nil
        }
    }
}
#endif
