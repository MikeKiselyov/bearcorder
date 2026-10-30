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
    static func runCapture(_ name: String, _ argument: String, _ parts: [String], _ app: AppState) async -> String? {
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

        case "browser-accessibility-off":
            // Undo what web-area asked of the browser, so it does not keep the page tree up to date.
            guard let pid = browserWithAccessibility else { return "nothing to undo" }
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanFalse)
            browserWithAccessibility = nil
            return "off"

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
            let a = ScrollStitching.rowSignatures(first)
            let b = ScrollStitching.rowSignatures(second)
            let best = ScrollStitcher.bestShift(previous: a, next: b)
            var flatA = 0
            for row in a where row == nil { flatA += 1 }
            return "rows=\(a.count) flat=\(flatA) best=\(best.shift ?? -1)@err\(String(format: "%.1f", best.error)) next=\(String(format: "%.1f", best.runnerUp))/\(best.compared) diag=\(ScrollStitcher.diagnose(previous: a, next: b, shift: 488))"

        case "copy-text-file":
            // copy-text-file:<path>: what ⌥⇧O does after the area is picked, on a picture from a file.
            guard let image = ImageFiles.load(URL(fileURLWithPath: argument)) else { return "no image" }
            Toast.shared.hide()
            NSPasteboard.general.clearContents()
            await AppState.shared.copyText(from: image)
            let copied = NSPasteboard.general.string(forType: .string) ?? ""
            return "toast=\(Toast.shared.isShowing) copied=\(copied.replacingOccurrences(of: "\n", with: " | "))"

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
                var stagedFiles = 0
                for name in (try? FileManager.default.contentsOfDirectory(atPath: updated.folder.path)) ?? [] where name.hasPrefix("staged-") {
                    stagedFiles += 1
                }
                if updated.kind == .screenshot {
                    guard let image = ImageFiles.load(updated.mediaURL) else { return "no image" }
                    let marks = FileManager.default.fileExists(atPath: updated.projectURL.path)
                    return "selected=\(updated.selectedScreen ?? "?") size=\(image.width)x\(image.height) project=\(marks) staged=\(stagedFiles)"
                }
                guard let track = try await AVURLAsset(url: updated.mediaURL).loadTracks(withMediaType: .video).first else { return "no track" }
                let size = try await track.load(.naturalSize)
                return String(format: "selected=%@ size=%dx%d duration=%.2f took=%.2fs staged=%d", updated.selectedScreen ?? "?", Int(size.width), Int(size.height), updated.duration, Date().timeIntervalSince(started), stagedFiles)
            } catch {
                let details = error as NSError
                return "error \(details.domain) \(details.code) \(details.userInfo)"
            }

        default:
            return nil
        }
    }
}
#endif
