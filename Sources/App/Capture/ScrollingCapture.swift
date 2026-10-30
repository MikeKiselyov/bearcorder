import AppKit
import AppCore
import ScreenCaptureKit

/// Scrolling screenshot: pick an area, the app scrolls it with the mouse wheel and glues the frames
/// into one long image. Esc stops early. Needs Accessibility (to scroll) and Screen Recording.
@MainActor
final class ScrollingCapture {
    static let shared = ScrollingCapture()

    static let maxFrames = 40
    static let maxHeightPixels = 30_000

    private var stopRequested = false
    private var escapeMonitors: [Any] = []
    private(set) var isRunning = false

    enum Failure: Error {
        case noAccessibility
        case noDisplay
        case nothingCaptured
    }

    /// Returns the long image, or nil if cancelled.
    func run(on screen: NSScreen, area: RegionSelector.Selection) async throws -> CGImage? {
        guard AXIsProcessTrusted() else { throw Failure.noAccessibility }
        isRunning = true
        stopRequested = false
        watchEscape()
        defer {
            isRunning = false
            stopWatchingEscape()
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayID = AppState.displayID(of: screen)
        guard let display = content.displays.first(where: { item in item.displayID == displayID }) else { throw Failure.noDisplay }
        var ours: [SCRunningApplication] = []
        for app in content.applications where app.bundleIdentifier == Bundle.main.bundleIdentifier {
            ours.append(app)
        }
        let filter = SCContentFilter(display: display, excludingApplications: ours, exceptingWindows: [])
        let pointRect = CGRect(x: area.normalized.minX * screen.frame.width, y: area.normalized.minY * screen.frame.height, width: area.normalized.width * screen.frame.width, height: area.normalized.height * screen.frame.height)
        let scale = screen.backingScaleFactor
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = pointRect
        configuration.width = Int(pointRect.width * scale)
        configuration.height = Int(pointRect.height * scale)
        configuration.showsCursor = false

        // The wheel scrolls whatever is under the pointer: move it to the middle of the area with a real
        // mouse-moved event (a warp would mute the next events for a moment).
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let center = CGPoint(x: area.global.midX, y: mainHeight - area.global.midY)
        let savedPointer = NSEvent.mouseLocation
        Toast.shared.show(L("capture.scrolling.inProgress"), symbol: "arrow.down.to.line", seconds: 30)
        movePointer(to: center)
        try? await Task.sleep(nanoseconds: 200_000_000)
        defer {
            Toast.shared.hide()
            movePointer(to: CGPoint(x: savedPointer.x, y: mainHeight - savedPointer.y))
        }

        var frames: [CGImage] = []
        var signatures: [[[UInt8]?]] = []
        var shifts: [Int] = []
        // 40% of the area per step: neighbouring frames share most rows, which keeps matching reliable.
        let scrollPoints = max(40, Int(pointRect.height * 0.4))
        var totalHeight = 0
        // Which wheel direction moves the page down depends on "natural scrolling"; found on the first scroll.
        var direction: Int32 = -1
        var directionKnown = false
        var attempts = 0
        while frames.count < ScrollingCapture.maxFrames && attempts < ScrollingCapture.maxFrames + 4 {
            attempts += 1
            if stopRequested { break }
            var frame = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            var rows = ScrollStitching.rowSignatures(frame)
            if let previous = signatures.last, !ScrollStitcher.isSame(previous, rows), ScrollStitcher.offset(previous: previous, next: rows) == nil {
                // Probably caught mid-animation (smooth scrolling, the bounce at the end): look again.
                try? await Task.sleep(nanoseconds: 700_000_000)
                frame = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                rows = ScrollStitching.rowSignatures(frame)
            }
            if let previous = signatures.last {
                let down = ScrollStitcher.bestShift(previous: previous, next: rows)
                Log.info("scrolling capture: frame \(frames.count + 1) same=\(ScrollStitcher.isSame(previous, rows)) shift=\(down.shift ?? -1) error=\(String(format: "%.1f", down.error))")
                if ScrollStitcher.isSame(previous, rows) {
                    if !directionKnown {
                        // Nothing moved: we may be scrolling up at the top. Try the other way once.
                        direction = -direction
                        directionKnown = true
                        scroll(by: scrollPoints, direction: direction)
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        continue
                    }
                    break
                }
                if let shift = ScrollStitcher.offset(previous: previous, next: rows) {
                    directionKnown = true
                    shifts.append(shift)
                    totalHeight += shift
                } else if !directionKnown, ScrollStitcher.offset(previous: rows, next: previous) != nil {
                    // The page went up instead: flip, and start again from this higher frame.
                    direction = -direction
                    directionKnown = true
                    frames = [frame]
                    signatures = [rows]
                    totalHeight = frame.height
                    scroll(by: scrollPoints, direction: direction)
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    continue
                } else {
                    Log.info("scrolling capture: frames do not line up, stopping")
                    if let last = frames.last {
                        ImageFiles.write(last, to: AppPaths.temporary.appendingPathComponent("scroll-fail-a.png"), type: "public.png")
                        ImageFiles.write(frame, to: AppPaths.temporary.appendingPathComponent("scroll-fail-b.png"), type: "public.png")
                    }
                    break
                }
            } else {
                totalHeight = frame.height
            }
            frames.append(frame)
            signatures.append(rows)
            if totalHeight >= ScrollingCapture.maxHeightPixels { break }
            scroll(by: scrollPoints, direction: direction)
            try? await Task.sleep(nanoseconds: 450_000_000)
        }
        if frames.isEmpty { throw Failure.nothingCaptured }
        Log.info("scrolling capture: \(frames.count) frames, \(totalHeight) px")
        return ScrollStitching.stitch(frames: frames, shifts: shifts, signatures: signatures)
    }

    /// Diagnostics for automation: scroll once, then report when and how far the content moved.
    func probe(on screen: NSScreen, area: RegionSelector.Selection, points: Int) async throws -> String {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayID = AppState.displayID(of: screen)
        guard let display = content.displays.first(where: { item in item.displayID == displayID }) else { throw Failure.noDisplay }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let pointRect = CGRect(x: area.normalized.minX * screen.frame.width, y: area.normalized.minY * screen.frame.height, width: area.normalized.width * screen.frame.width, height: area.normalized.height * screen.frame.height)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = pointRect
        configuration.width = Int(pointRect.width * screen.backingScaleFactor)
        configuration.height = Int(pointRect.height * screen.backingScaleFactor)
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        movePointer(to: CGPoint(x: area.global.midX, y: mainHeight - area.global.midY))
        try? await Task.sleep(nanoseconds: 200_000_000)
        let firstImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        ImageFiles.write(firstImage, to: AppPaths.temporary.appendingPathComponent("probe-0.png"), type: "public.png")
        let first = ScrollStitching.rowSignatures(firstImage)
        var flatRows = 0
        for row in first where row == nil {
            flatRows += 1
        }
        scroll(by: points, direction: -1)
        var report: [String] = []
        var waited = 0
        for delay in [100, 250, 500, 1000, 2000] {
            try? await Task.sleep(nanoseconds: UInt64((delay - waited) * 1_000_000))
            waited = delay
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            ImageFiles.write(image, to: AppPaths.temporary.appendingPathComponent("probe-\(delay).png"), type: "public.png")
            let rows = ScrollStitching.rowSignatures(image)
            let down = ScrollStitcher.bestShift(previous: first, next: rows)
            let up = ScrollStitcher.bestShift(previous: rows, next: first)
            report.append("\(delay)ms same=\(ScrollStitcher.isSame(first, rows)) down=\(down.shift ?? -1)@err\(String(format: "%.1f", down.error)) up=\(up.shift ?? -1)@err\(String(format: "%.1f", up.error))")
        }
        return "rows=\(first.count) flat=\(flatRows) " + report.joined(separator: " | ")
    }

    private func scroll(by points: Int, direction: Int32) {
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1, wheel1: direction * Int32(points), wheel2: 0, wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }

    /// `point` in top-left screen coordinates.
    private func movePointer(to point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        event?.post(tap: .cghidEventTap)
    }

    private func watchEscape() {
        let handler: (NSEvent) -> Void = { event in
            if event.keyCode == 53 {
                MainActor.assumeIsolated {
                    ScrollingCapture.shared.stopRequested = true
                }
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown], handler: handler) {
            escapeMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { event in
            handler(event)
            return event
        }) {
            escapeMonitors.append(local)
        }
    }

    private func stopWatchingEscape() {
        for monitor in escapeMonitors {
            NSEvent.removeMonitor(monitor)
        }
        escapeMonitors.removeAll()
    }
}
