// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AVFoundation
import AVKit
import AppKit
import BugbearCore
import SwiftUI

@MainActor
extension DevChecks {
    // MARK: Snapshots

    static func snapshot(folder: URL) async -> Int32 {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let app = AppState.shared
        app.environmentPreview = EnvironmentSnapshot(osVersion: "15.1", osBuild: "24B83", display: "2560×1440 @2x", appName: "Chrome", appVersion: "131.0", url: "stage.myapp.com/checkout", locale: "en-PT")
        app.activity = [0.3, 0.45, 0.25, 0.6, 0.4, 0.35, 0.7, 0.5, 0.3, 0.55, 0.45, 0.65, 0.8, 0.95, 0.75, 0.85]
        app.coveredSeconds = 180
        app.bufferState = .running

        Updater.shared.state = .available(UpdateInfo(version: "0.6.0", newCommitCount: 9, changes: [
            UpdateInfo.Change(title: "Pick screenshot and video quality with the file size (0.8.0)", shortSHA: "3333333", pullRequest: 9),
            UpdateInfo.Change(title: "Space: clear delete confirmation in the menu panel (0.8.1)", shortSHA: "2222222", pullRequest: 11),
        ]))
        render(UpdateBadge(detailsOnly: true).padding(16).auroraBackground().environment(app).preferredColorScheme(.dark), size: CGSize(width: 360, height: 260), to: folder.appendingPathComponent("update-badge.png"))

        await renderSpaceReview(folder: folder, app: app)

        for kind in FeedbackReport.Kind.allCases {
            let model = FeedbackModel(kind: kind)
            if kind == .problem {
                model.title = "The saved clip is black"
                model.details = "Saved the last minute with Option + Shift + 1, the clip plays but stays black."
            } else {
                model.title = "Blur faces automatically"
                model.details = "Find faces on a screenshot and blur them before I share it."
            }
            render(FeedbackView(model: model).environment(app).preferredColorScheme(.dark), size: CGSize(width: 560, height: 600), to: folder.appendingPathComponent("feedback-\(kind.rawValue).png"))
        }

        let crashModel = FeedbackModel(kind: .problem)
        crashModel.title = "Bugbear quit unexpectedly"
        crashModel.crash = "EXC_BREAKPOINT (SIGTRAP)"
        crashModel.notice = "Bugbear quit unexpectedly last time. Sending a report with the crash details helps fix it. Add what you were doing, if you remember."
        render(FeedbackView(model: crashModel).environment(app).preferredColorScheme(.dark), size: CGSize(width: 560, height: 640), to: folder.appendingPathComponent("feedback-crash.png"))

        await withMadeUpSpaceHome {
            for tab in MenuTab.allCases {
                UserDefaults.standard.set(tab.rawValue, forKey: "menuTab")
                render(MenuBarView().environment(app), size: CGSize(width: 360, height: 719), to: folder.appendingPathComponent("menu-\(tab.rawValue.lowercased()).png"))
                let natural = NSHostingView(rootView: MenuBarView().environment(app)).fittingSize
                print("menu \(tab.rawValue) natural height: \(Int(natural.height))")
            }
        }

        render(WhatsNewView(releases: WhatsNewCatalog.releases, changes: ["Fix menu panel height", "Add regex tester", "Faster export"]).preferredColorScheme(.dark), size: CGSize(width: 720, height: 1100), to: folder.appendingPathComponent("whats-new.png"))

        let screenSize = CGSize(width: 1512, height: 982)
        let picker = RegionSelectionView(frame: CGRect(origin: .zero, size: screenSize))
        picker.selection = CGRect(x: 436, y: 241, width: 640, height: 360)
        renderAppKit(picker, to: folder.appendingPathComponent("record-area-picker.png"))
        let outline = RecordingOutlineView(frame: CGRect(origin: .zero, size: screenSize))
        outline.recordedRect = CGRect(x: 436, y: 381, width: 640, height: 360)
        outline.drawsHandles = true
        renderAppKit(outline, to: folder.appendingPathComponent("record-outline-area.png"))
        let other = RecordingOutlineView(frame: CGRect(origin: .zero, size: CGSize(width: 1200, height: 700)))
        renderAppKit(other, to: folder.appendingPathComponent("record-outline-other-display.png"))
        renderAreaAcrossDisplays(to: folder.appendingPathComponent("record-area-across.png"))

        for page in 0..<6 {
            render(OnboardingView(startPage: page).environment(app).preferredColorScheme(.dark), size: CGSize(width: 680, height: 600), to: folder.appendingPathComponent("onboarding-\(page + 1).png"))
        }

        let tools: [ToolKind] = [.json, .xml, .sql, .jwt, .time, .timeZones, .dataConvert, .quick, .generate, .base64, .testData, .regex, .qr, .jsonDiff, .jsonPath, .http, .cron, .length, .contrast]
        let samples: [ToolKind: String] = [
            .jsonDiff: #"{"id":5,"status":"PAID","total":49.0,"items":[{"sku":"A"},{"sku":"B"}]}"#,
            .jsonPath: #"{"orderId":"ORD-58213","items":[{"id":1,"price":49},{"id":2,"price":99}],"customer":{"id":7781}}"#,
            .http: "POST /api/orders?debug=1&lang=en HTTP/1.1\nHost: stage.example.com\nAuthorization: Bearer eyJhbGciOi...\nCookie: session=abc123; theme=dark\nContent-Type: application/json\n\n{\"sku\":\"SUB-PRO-M\",\"qty\":1}",
            .cron: "30 9 * * 1-5",
            .json: #"{"orderId":"ORD-58213","status":"FAILED","total":-49.00,"currency":"EUR","customer":{"id":7781,"email":"test.qa@myapp.com"},"items":[{"sku":"SUB-PRO-M","qty":1,"price":49.00}],"error":{"code":"PAYMENT_DECLINED","message":null},"createdAt":"2026-10-24T10:58:12Z"}"#,
            .xml: "<order id=\"5\"><item sku=\"A\">Pro</item><item sku=\"B\">Team</item><total>49.00</total></order>",
            .sql: "select o.id, o.total, u.email from orders o join users u on u.id = o.user_id where o.total < 0 and o.created_at > now() - interval '1 day' order by o.id desc limit 50",
            .jwt: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI3NzgxIiwiZW1haWwiOiJ0ZXN0LnFhQG15YXBwLmNvbSIsInJvbGUiOiJxYSIsImlhdCI6MTc5MjgzNTg5MiwiZXhwIjoxNzkyODM5NDkyfQ.signature",
            .time: "1792839492",
            .dataConvert: #"[{"id":1,"user":{"name":"Ann"},"total":5},{"id":2,"user":{"name":"Bob"},"total":7.5}]"#,
            .base64: "eyJ0ZXN0IjoiaGVsbG8gd29ybGQifQ==",
        ]
        for tool in tools {
            let view = ToolboxView(initialTool: tool, initialInput: samples[tool] ?? "", detectedFromClipboard: tool == .json)
                .environment(app)
                .preferredColorScheme(.dark)
            render(view, size: CGSize(width: 1220, height: 760), to: folder.appendingPathComponent("toolbox-\(tool.id.lowercased().filter { character in character.isLetter }).png"))
        }

        // One picture per Settings page; "settings.png" is the first, as before.
        let shownPage = SettingsNavigation.shared.page
        for page in SettingsPage.allCases {
            SettingsNavigation.shared.page = page
            var name = "settings-\(page.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")).png"
            if page == .general {
                name = "settings.png"
            }
            render(SettingsView().environment(app).preferredColorScheme(.dark), size: CGSize(width: 780, height: 900), to: folder.appendingPathComponent(name))
        }
        SettingsNavigation.shared.page = shownPage
        render(HistoryView().environment(app).preferredColorScheme(.dark), size: CGSize(width: 980, height: 680), to: folder.appendingPathComponent("history.png"))
        render(RecordingHUDView().environment(app).preferredColorScheme(.dark), size: CGSize(width: 700, height: 44), to: folder.appendingPathComponent("hud.png"))
        app.overlay.isDrawing = true
        let shownTool = app.overlay.tool
        app.overlay.tool = .text
        render(RecordingHUDView().environment(app).preferredColorScheme(.dark), size: CGSize(width: 940, height: 44), to: folder.appendingPathComponent("hud-drawing.png"))
        app.overlay.tool = shownTool
        app.overlay.isDrawing = false
        app.recording = RecordingSession()
        render(RecordingHUDView().environment(app).preferredColorScheme(.dark), size: CGSize(width: 700, height: 44), to: folder.appendingPathComponent("hud-recording.png"))
        app.recording = nil

        if let menuBar = Logo.menuBarImage(recording: true).cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ImageFiles.write(menuBar, to: folder.appendingPathComponent("menubar-glyph.png"), type: "public.png")
        }
        print("Snapshots written to \(folder.path)")
        return 0
    }

    /// AppKit views (area picker, recording outline) over a grey "desktop".
    /// A laptop and a smaller monitor beside it, an area recorded across both (What's New). Each
    /// screen is drawn on its own, the way the other pictures are, then put on one desk.
    private static func renderAreaAcrossDisplays(to url: URL) {
        let deskSize = CGSize(width: 2712, height: 982)
        let area = CGRect(x: 1100, y: 330, width: 640, height: 360)
        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 140, width: 1200, height: 750)]
        // Two shades, so the seam between the displays shows inside the area too.
        let colors: [UInt32] = [0x6B7280, 0x7C8494]
        let scale: CGFloat = 2
        guard let desk = CGContext(data: nil, width: Int(deskSize.width * scale), height: Int(deskSize.height * scale), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        desk.setFillColor(NSColor(hex: 0x16171A).cgColor)
        desk.fill(CGRect(origin: .zero, size: CGSize(width: deskSize.width * scale, height: deskSize.height * scale)))
        for (index, frame) in screens.enumerated() {
            let outline = RecordingOutlineView(frame: CGRect(origin: .zero, size: frame.size))
            outline.recordedRect = area.offsetBy(dx: -frame.minX, dy: -frame.minY)
            outline.labelScale = 2
            outline.showsLabel = index == 0
            outline.drawsHandles = true
            // On screen the grip is one window; here the laptop, which has room above the area, draws it.
            outline.drawsGrip = index == 0
            let container = NSView(frame: outline.frame)
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor(hex: colors[index]).cgColor
            container.addSubview(outline)
            guard let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds) else { continue }
            container.cacheDisplay(in: container.bounds, to: bitmap)
            guard let image = bitmap.cgImage else { continue }
            desk.draw(image, in: CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale))
        }
        if let image = desk.makeImage() {
            ImageFiles.write(image, to: url, type: "public.png")
        }
    }

    static func renderAppKit(_ view: NSView, to url: URL) {
        let container = NSView(frame: view.frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(hex: 0x6B7280).cgColor
        container.addSubview(view)
        guard let bitmap = container.bitmapImageRepForCachingDisplay(in: container.bounds) else { return }
        container.cacheDisplay(in: container.bounds, to: bitmap)
        if let image = bitmap.cgImage {
            ImageFiles.write(image, to: url, type: "public.png")
        }
    }

    static func render<Content: View>(_ view: Content, size: CGSize, to url: URL) {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height).auroraBackground())
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }
}
#endif
