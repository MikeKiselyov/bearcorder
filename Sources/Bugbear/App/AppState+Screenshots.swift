import AppKit
import ScreenCaptureKit
import Observation
import BugbearCore
import QuartzCore

extension AppState {
    // MARK: Screenshots

    func takeScreenshot(_ mode: ScreenshotMode) async {
        let started = Date()
        let panelWasOpen = isMenuPanelOpen
        closeMenuPanel()
        let app = lastExternalApp
        if panelWasOpen {
            // Let the panel fade out so it is not in the picture.
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        let recentEvents = inputRecorder.recentEvents(seconds: 60)
        // Collected while the person picks the area: reading the browser tab can take a moment.
        async let collected = EnvironmentCollector.snapshot(for: app, readURL: settings.readBrowserURL)

        if (mode == .fullScreen || mode == .allDisplays) && NSScreen.screens.count > 1 {
            let displays = await ScreenshotCapture.captureEachDisplay()
            let environment = await collected
            saveScreenshotOfEachDisplay(displays, showAll: mode == .allDisplays, environment: environment, events: recentEvents, started: started)
            return
        }
        guard let file = await ScreenshotCapture.capture(mode) else { return }
        let captured = Date()
        let environment = await collected
        do {
            let capture = try store.add(kind: .screenshot, mediaFile: file, environment: environment, events: recentEvents)
            announceScreenshot(capture)
            WindowManager.shared.openEditor(for: capture)
            Log.info(String(format: "screenshot: picked in %.2fs, editor after %.2fs more", captured.timeIntervalSince(started), Date().timeIntervalSince(captured)))
        } catch {
            showError(error.localizedDescription)
        }
    }


    /// Puts a new screenshot on the clipboard (Settings → Screenshots) and says so.
    private func announceScreenshot(_ capture: Capture) {
        guard settings.copyScreenshots, let png = try? Data(contentsOf: capture.mediaURL) else {
            Toast.shared.show(L("app.screenshot.saved"), symbol: "photo")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // Image data for chat apps, plus the file for Finder and Jira attachments.
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setString(capture.mediaURL.absoluteString, forType: .fileURL)
        pasteboard.writeObjects([item])
        justCopiedScreenshot = capture.id
        Toast.shared.showCopied(L("app.screenshot.copied"), preview: L("app.screenshot.copied.alsoSaved"), symbol: "photo")
    }

    /// Several displays: every display as its own picture, like clips. The side-by-side picture is built
    /// right after the editor opens, so the editor does not wait for it. The editor opens on the display
    /// under the pointer, or side by side for "All displays".
    private func saveScreenshotOfEachDisplay(_ displays: [(displayID: CGDirectDisplayID, frame: CGRect, url: URL)], showAll: Bool, environment: EnvironmentSnapshot, events: [InputEvent], started: Date) {
        if displays.isEmpty {
            showError(L("app.screenshot.failed"))
            return
        }
        if displays.count == 1 {
            // A display went to sleep or was unplugged: keep the one picture that came back.
            do {
                let capture = try store.add(kind: .screenshot, mediaFile: displays[0].url, environment: environment, events: events)
                announceScreenshot(capture)
                WindowManager.shared.openEditor(for: capture)
            } catch {
                showError(error.localizedDescription)
            }
            return
        }
        var variants: [ScreenVariant] = []
        for display in displays {
            variants.append(ScreenVariant(id: "display-\(display.displayID)", name: AppState.screenName(display.displayID), file: "screen-\(display.displayID).png", events: events, isMain: display.displayID == CGMainDisplayID()))
        }
        variants.append(ScreenVariant(id: ScreenVariant.allID, name: L("app.display.sideBySide"), file: "screen-all.png", events: events, isMain: false))

        var chosen = 0
        let mouse = NSEvent.mouseLocation
        for (index, display) in displays.enumerated() where display.frame.contains(mouse) {
            chosen = index
        }
        do {
            if showAll {
                // Stitched now: it is the picture that opens.
                var images: [CGImage] = []
                for display in displays {
                    if let image = ImageFiles.load(display.url) {
                        images.append(image)
                    }
                }
                let stitchedFile = AppPaths.temporary.appendingPathComponent("all-\(UUID().uuidString).png")
                if let stitched = ScreenshotCapture.stitchHorizontally(images) {
                    ImageFiles.write(stitched, to: stitchedFile, type: "public.png")
                }
                var capture = try store.add(kind: .screenshot, mediaFile: stitchedFile, environment: environment, events: events)
                try FileManager.default.linkItem(at: capture.mediaURL, to: capture.folder.appendingPathComponent("screen-all.png"))
                for (index, display) in displays.enumerated() {
                    try FileManager.default.moveItem(at: display.url, to: capture.folder.appendingPathComponent(variants[index].file))
                }
                capture.screens = variants
                capture.selectedScreen = ScreenVariant.allID
                try store.replace(capture)
                announceScreenshot(capture)
                WindowManager.shared.openEditor(for: capture)
            } else {
                var capture = try store.add(kind: .screenshot, mediaFile: displays[chosen].url, environment: environment, events: events)
                for (index, display) in displays.enumerated() {
                    let target = capture.folder.appendingPathComponent(variants[index].file)
                    if index == chosen {
                        try FileManager.default.linkItem(at: capture.mediaURL, to: target)
                    } else {
                        try FileManager.default.moveItem(at: display.url, to: target)
                    }
                }
                capture.screens = variants
                capture.selectedScreen = variants[chosen].id
                try store.replace(capture)
                announceScreenshot(capture)
                WindowManager.shared.openEditor(for: capture)
                let ready = capture
                Task.detached(priority: .utility) {
                    CaptureStore.buildSideBySideScreenshot(ready)
                }
            }
            Log.info(String(format: "screenshot of %d displays: editor after %.2fs", displays.count, Date().timeIntervalSince(started)))
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// ⌥⇧O: select an area, its text goes to the clipboard. Nothing is added to history.
    func copyTextFromScreen() async {
        closeMenuPanel()
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard let file = await ScreenshotCapture.capture(.area) else { return }
        defer { try? FileManager.default.removeItem(at: file) }
        guard let image = ImageFiles.load(file) else { return }
        await copyText(from: image)
    }

    /// The text in a picture (or the link of a QR code in it) to the clipboard, with a message saying
    /// it can be pasted.
    func copyText(from image: CGImage) async {
        // A QR code in the area: its link is more useful than the text around it.
        let codes = await QRCode.read(image)
        if !codes.isEmpty {
            let payload = codes.joined(separator: "\n")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(payload, forType: .string)
            var preview = payload
            if preview.count > 40 {
                preview = String(preview.prefix(40)) + "…"
            }
            Toast.shared.showCopied(L("app.copyText.qrCopied"), preview: preview, symbol: "qrcode")
            return
        }
        do {
            let lines = try await TextRecognizer.recognize(image)
            let text = TextRecognizer.text(of: lines)
            if text.isEmpty {
                Toast.shared.show(L("app.copyText.noText"), symbol: "text.viewfinder")
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            var preview = text.replacingOccurrences(of: "\n", with: " ")
            if preview.count > 40 {
                preview = String(preview.prefix(40)) + "…"
            }
            Log.info("copied \(text.count) characters of recognized text")
            Toast.shared.showCopied(L("app.copyText.copied"), preview: preview, symbol: "text.viewfinder")
        } catch {
            showError(L("app.copyText.failed", error.localizedDescription))
        }
    }

    // MARK: Scrolling screenshot

    /// Pick an area, then the app scrolls it and glues the frames into one long screenshot.
    func takeScrollingScreenshot() async {
        if ScrollingCapture.shared.isRunning { return }
        closeMenuPanel()
        if !InputEventRecorder.hasAccessibilityAccess {
            requestAccessibilityAccess()
            Toast.shared.show(L("app.scrolling.needsAccessibility", AppInfo.name), symbol: "lock.fill", seconds: 4)
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { item in item.frame.contains(mouse) } ?? NSScreen.main
        guard let chosen = screen, let area = await regionSelector.pick(on: chosen, initial: nil, confirmTitle: L("app.scrolling.captureButton"), showsSizes: false) else { return }
        let app = lastExternalApp
        // Let the picker disappear before the first frame.
        try? await Task.sleep(nanoseconds: 300_000_000)
        do {
            guard let image = try await ScrollingCapture.shared.run(on: chosen, area: area) else { return }
            let file = AppPaths.temporary.appendingPathComponent("scroll-\(UUID().uuidString).png")
            ImageFiles.write(image, to: file, type: "public.png")
            let environment = await EnvironmentCollector.snapshot(for: app, readURL: settings.readBrowserURL)
            let capture = try store.add(kind: .screenshot, mediaFile: file, environment: environment)
            Toast.shared.show(L("app.scrolling.done", image.height), symbol: "arrow.down.to.line", seconds: 2)
            WindowManager.shared.openEditor(for: capture)
        } catch ScrollingCapture.Failure.noAccessibility {
            requestAccessibilityAccess()
        } catch {
            showError(L("app.scrolling.failed", error.localizedDescription))
        }
    }

    // MARK: Screen checks

    /// Resizes the front window of the app you were using (needs Accessibility).
    func resizeFrontWindow(to preset: WindowResizer.Preset) {
        closeMenuPanel()
        let app = lastExternalApp
        switch WindowResizer.resize(app: app, to: preset.size) {
        case .success(let size):
            let name = app?.localizedName ?? L("app.resize.window")
            var text = L("app.resize.result", name, Int(size.width), Int(size.height))
            let wider = size.width > preset.size.width + 1
            let smaller = size.width < preset.size.width - 1 || size.height < preset.size.height - 1
            if wider && AppState.isBrowser(app) {
                text += ". " + L("app.resize.needsResponsiveMode", Int(size.width))
            } else if wider {
                text += " " + L("app.resize.minimumWidth")
            } else if smaller {
                text += " " + L("app.resize.limitedByScreen")
            }
            Toast.shared.show(text, symbol: "macwindow", seconds: wider ? 5 : 2)
        case .failure(.noAccess):
            requestAccessibilityAccess()
            Toast.shared.show(L("app.resize.needsAccessibility", AppInfo.name), symbol: "lock.fill", seconds: 3)
        case .failure(.noApp), .failure(.noWindow):
            Toast.shared.show(L("app.resize.noWindow"), symbol: "macwindow", seconds: 3)
        case .failure(.refused):
            Toast.shared.show(L("app.resize.notResizable"), symbol: "macwindow", seconds: 3)
        }
    }

    static func isBrowser(_ app: NSRunningApplication?) -> Bool {
        let browsers = ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.brave.Browser", "com.operasoftware.Opera"]
        return browsers.contains(app?.bundleIdentifier ?? "")
    }

    func startRuler() {
        closeMenuPanel()
        ScreenRuler.shared.start()
    }

    func pickColor() {
        closeMenuPanel()
        Task { await ColorPick.pickAndCopy() }
    }

    func openDesignOverlay(fromClipboard: Bool) {
        closeMenuPanel()
        if fromClipboard {
            if !DesignOverlay.shared.openFromClipboard() {
                Toast.shared.show(L("app.clipboard.noImage"), symbol: "photo", seconds: 3)
            }
        } else {
            DesignOverlay.shared.openFromFile()
        }
    }
}
