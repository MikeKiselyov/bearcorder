// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AVFoundation
import AVKit
import AppKit
import BugbearCore
import SwiftUI

/// Developer checks that need no permissions, run from the command line:
///   Bugbear --self-test <folder>   media pipeline checks, writes sample outputs
///   Bugbear --snapshot <folder>    renders every screen to PNG
@MainActor
enum DevChecks {
    private static var failures: [String] = []

    private static func renderTextImage(_ lines: [String]) -> CGImage? {
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
    private static func pixel(_ image: CGImage, at point: CGPoint) -> (red: Int, green: Int, blue: Int)? {
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
    private static func renderTallImage(_ lines: [String]) -> CGImage? {
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

    private static func check(_ condition: Bool, _ name: String, _ detail: String = "") {
        if condition {
            print("PASS  \(name)")
        } else {
            print("FAIL  \(name) \(detail)")
            failures.append(name)
        }
    }

    // MARK: Self test

    /// The five color slots: they start as the usual colors, dragging in the color panel changes the
    /// first slot, a new opening adds one on the left, and there are always five.
    private static func checkRecentColors() async {
        // On scratch defaults: the person's palette is never touched.
        let domain = "bugbear.selftest.colors.\(UUID().uuidString)"
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

    /// Two names of one file (how original.* points at a display's file) are recognized as one file,
    /// so picking the display already shown swaps nothing.
    private static func checkSameFile(folder: URL) {
        let files = FileManager.default
        let first = folder.appendingPathComponent("same-file-a.bin")
        let link = folder.appendingPathComponent("same-file-b.bin")
        let other = folder.appendingPathComponent("same-file-c.bin")
        for url in [first, link, other] {
            try? files.removeItem(at: url)
        }
        try? Data([1, 2, 3]).write(to: first)
        try? Data([1, 2, 3]).write(to: other)
        try? files.linkItem(at: first, to: link)
        check(CaptureStore.isSameFile(first, link), "a hard link is the same file")
        check(!CaptureStore.isSameFile(first, other), "an equal copy is another file")
    }

    /// Every picture a release note names loads, so the card shows it instead of nothing.
    /// A new language is a new folder: a made-up resources bundle with English and German tables
    /// picks German for a German speaker, English for others, and English for a key German lacks.
    private static func checkLocalization(folder: URL) {
        check(L("feedback.kind.problem") == "Report a problem", "the app's English text comes from en.lproj", L("feedback.kind.problem"))
        check(L("feedback.kind.tip", "Bugbear") == "Problems and ideas go to the Bugbear repository on GitHub as issues", "values go into the text", L("feedback.kind.tip", "Bugbear"))
        check(L("feedback.no.such.key") == "feedback.no.such.key", "a missing key shows as itself")
        // Counts come from .stringsdict: the word follows the number.
        check(L("history.count", 1) == "1 capture" && L("history.count", 5) == "5 captures", "a count picks one or many", "\(L("history.count", 1)) / \(L("history.count", 5))")
        check(L("settings.storage.usedValue", "2 GB", 1) == "2 GB · 1 capture", "a count among other values", L("settings.storage.usedValue", "2 GB", 1))
        check(L("history.compare.summary", 3, "1.5") == "3 changed areas · 1.5% of pixels", "a count with a percent sign", L("history.compare.summary", 3, "1.5"))
        // The copy button tells whether the report will have steps before it is pasted.
        let copyTitles = [L("capture.copyReport.title", 0), L("capture.copyReport.title", 1), L("capture.copyReport.title", 7)]
        check(copyTitles == ["Copy bug report · no steps", "Copy bug report · 1 step", "Copy bug report · 7 steps"], "the copy button says how many steps", copyTitles.joined(separator: " / "))
        let resources = folder.appendingPathComponent("l10n-check.bundle", isDirectory: true)
        try? FileManager.default.removeItem(at: resources)
        let tables: [(language: String, text: String)] = [
            (language: "en", text: "\"check.greeting\" = \"Hello\";\n\"check.only.english\" = \"English only\";\n"),
            (language: "de", text: "\"check.greeting\" = \"Hallo\";\n"),
        ]
        for table in tables {
            let lproj = resources.appendingPathComponent("\(table.language).lproj", isDirectory: true)
            try? FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
            try? table.text.write(to: lproj.appendingPathComponent("check.strings"), atomically: true, encoding: .utf8)
        }
        guard let bundle = Bundle(url: resources) else {
            check(false, "localization check bundle")
            return
        }
        let german = L10n.languageBundles(in: bundle, preferred: ["de-AT", "en"])
        let french = L10n.languageBundles(in: bundle, preferred: ["fr"])
        check(L10n.text(for: "check.greeting", in: german) == "Hallo", "a German speaker gets the German folder", L10n.text(for: "check.greeting", in: german))
        check(L10n.text(for: "check.greeting", in: french) == "Hello", "a language the app does not have falls back to English")
        check(L10n.text(for: "check.only.english", in: german) == "English only", "a key the language lacks falls back to English")
        // Russian has three forms for a count; a new language brings its own rules in its .stringsdict.
        // A bundle of its own: Bundle remembers the languages of a folder it has opened.
        let pluralResources = folder.appendingPathComponent("l10n-plural-check.bundle", isDirectory: true)
        try? FileManager.default.removeItem(at: pluralResources)
        try? FileManager.default.createDirectory(at: pluralResources.appendingPathComponent("en.lproj", isDirectory: true), withIntermediateDirectories: true)
        let russianFolder = pluralResources.appendingPathComponent("ru.lproj", isDirectory: true)
        try? FileManager.default.createDirectory(at: russianFolder, withIntermediateDirectories: true)
        let forms: [String: Any] = [
            "check.files": [
                "NSStringLocalizedFormatKey": "%#@files@",
                "files": ["NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "d", "one": "%d файл", "few": "%d файла", "many": "%d файлов", "other": "%d файла"],
            ],
        ]
        (forms as NSDictionary).write(to: russianFolder.appendingPathComponent("check.stringsdict"), atomically: true)
        guard let withRussian = Bundle(url: pluralResources) else { return }
        let russian = L10n.languageBundles(in: withRussian, preferred: ["ru"])
        let format = L10n.text(for: "check.files", in: russian)
        let russianLocale = Locale(identifier: "ru")
        var counted: [String] = []
        for count in [1, 3, 5, 21] {
            counted.append(String(format: format, locale: russianLocale, arguments: [count]))
        }
        check(counted == ["1 файл", "3 файла", "5 файлов", "21 файл"], "a language with three count forms picks the right one", counted.joined(separator: ", "))
    }

    /// The editor's player shows no controls and no Live Text layer that would take the drags.
    private static func checkPlayerView() {
        let view = PassivePlayerView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        PlayerView.configure(view)
        check(!view.allowsVideoFrameAnalysis, "the video editor player has no Live Text over the frame")
        check(view.hitTest(CGPoint(x: 100, y: 50)) == nil && !view.acceptsFirstResponder, "clicks and drags on the video go to the marks, not to the player")
        check(view.controlsStyle == .none, "the video editor player has no controls of its own")
    }

    private static func checkWhatsNewPictures() {
        for release in WhatsNewCatalog.releases {
            for item in release.items where !item.image.isEmpty {
                let picture = WhatsNewView.image(named: item.image)
                check(picture != nil && (picture?.size.width ?? 0) > 0, "what's new picture \(item.image) loads")
            }
        }
        check(WhatsNewView.image(named: "") == nil, "an item without a picture shows none")
        // In the built app the resources are in Contents/Resources: not in the root of the .app,
        // where they would break the signature.
        let resourcesPath = AppResources.bundle?.bundlePath ?? "none"
        if Bundle.main.bundlePath.hasSuffix(".app") {
            check(resourcesPath.hasSuffix(".app/Contents/Resources/\(AppResources.bundleName)"), "the app reads its resources from Contents/Resources", resourcesPath)
        } else {
            check(resourcesPath.hasSuffix("/\(AppResources.bundleName)"), "a build from .build reads its resources next to the executable", resourcesPath)
        }
    }

    /// Earlier users keep their crash clips; a new install and someone who chose keep their choice.
    /// The registered default of 7 days must not count as a choice, and someone who left the
    /// guide's 7 days as they were is not an earlier user.
    /// New marks start at line size 7 in the screenshot editor and when drawing on the screen.
    /// Tests choose picker and menu items without opening the menu: the choice reaches the binding
    /// and the menu's button runs, the same as a click in the open menu.
    private static func checkPopUpChoices() async {
        final class Choices {
            var indent = 2
            var pressed = ""
        }
        let choices = Choices()
        let indent = Binding(get: { choices.indent }, set: { value in choices.indent = value })
        let view = VStack {
            Picker("Indent", selection: indent) {
                Text("2 spaces").tag(2)
                Text("4 spaces").tag(4)
                Text("Tabs").tag(0)
            }
            .pickerStyle(.menu)
            Menu("Copy as…") {
                Button("Copy as YAML") { choices.pressed = "YAML" }
                Divider()
                Button("Copy as CSV") { choices.pressed = "CSV" }
            }
            .menuStyle(.borderlessButton)
        }
        .frame(width: 300, height: 120)
        let window = NSWindow(contentRect: CGRect(x: -2000, y: -2000, width: 300, height: 120), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        window.contentView?.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 300_000_000)
        let buttons = PopUpMenus.all(in: window.contentView ?? NSView())
        var listed: [String] = []
        for button in buttons {
            listed.append(PopUpMenus.items(of: button).joined(separator: ","))
        }
        check(buttons.count == 2, "a menu picker and a menu are pop-up buttons", "\(buttons.count): \(listed)")
        guard buttons.count == 2 else { return }
        let picker = buttons.first { button in !button.pullsDown } ?? buttons[0]
        let menu = buttons.first { button in button.pullsDown } ?? buttons[1]
        check(PopUpMenus.items(of: picker) == ["2 spaces", "4 spaces", "Tabs"], "a picker lists its choices", "\(listed)")
        check(PopUpMenus.items(of: menu) == ["Copy as YAML", "Copy as CSV"], "a menu lists its items without the separator", "\(listed)")
        let chose = PopUpMenus.choose("Tabs", in: picker)
        try? await Task.sleep(nanoseconds: 100_000_000)
        check(chose && choices.indent == 0, "choosing a picker item sets its value", "\(chose) \(choices.indent)")
        let pressed = PopUpMenus.choose("Copy as CSV", in: menu)
        try? await Task.sleep(nanoseconds: 100_000_000)
        check(pressed && choices.pressed == "CSV", "choosing a menu item runs its button", "\(pressed) \(choices.pressed)")
        check(!PopUpMenus.choose("Copy as PDF", in: menu), "a missing item is not chosen")
    }

    /// Tests type into fields without posting keys: the text reaches a SwiftUI binding, both for a
    /// text field and for a tool's code view.
    private static func checkTextInput() async {
        final class Texts {
            var search = ""
            var code = ""
        }
        let texts = Texts()
        let search = Binding(get: { texts.search }, set: { value in texts.search = value })
        let code = Binding(get: { texts.code }, set: { value in texts.code = value })
        let view = VStack {
            TextField("Search tools", text: search)
            CodeTextView(text: code)
                .frame(height: 80)
        }
        .frame(width: 300, height: 140)
        let window = NSWindow(contentRect: CGRect(x: -2000, y: -2000, width: 300, height: 140), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        window.contentView?.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 300_000_000)
        var field: NSTextField?
        var textView: NSTextView?
        var stack: [NSView] = [window.contentView ?? NSView()]
        while let current = stack.popLast() {
            if let found = current as? NSTextField, found.isEditable {
                field = found
            }
            if let found = current as? NSTextView {
                textView = found
            }
            for child in current.subviews {
                stack.append(child)
            }
        }
        guard let searchField = field, let codeView = textView else {
            check(false, "a text field and a code view to type into", "\(String(describing: field)) \(String(describing: textView))")
            return
        }
        let typedSearch = TextInput.type("cron", into: searchField)
        let typedCode = TextInput.type("{\"a\": 1}\nline two", into: codeView)
        try? await Task.sleep(nanoseconds: 100_000_000)
        check(typedSearch && texts.search == "cron", "typing into a text field reaches its binding", texts.search)
        check(typedCode && texts.code == "{\"a\": 1}\nline two", "typing into a code view reaches its binding", texts.code)
        let center = window.convertToScreen(searchField.convert(searchField.bounds, to: nil))
        let screenHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let found = TextInput.view(at: CGPoint(x: center.midX, y: screenHeight - center.midY), in: window)
        check(found === searchField, "the text field under a point is found", "\(String(describing: found))")
    }

    /// The area picker draws its buttons by hand; VoiceOver and the tests still find them, at the
    /// place they are drawn, and pressing them does what a click does.
    /// A control being laid out can report a NaN frame; naming it must not stop the app (Int(NaN) traps).
    /// Opening an old capture applies which fields show and their names, but keeps the values your
    /// fields had then; a change made while the editor is open takes the new values too.
    private static func checkFieldSettingsOnOldCaptures() {
        var taken = EnvironmentSnapshot()
        taken.extras = [EnvironmentSnapshot.Field(name: "Build", value: "1.42")]
        let now = EnvironmentCollector.FieldSettings(extras: [EnvironmentSnapshot.Field(name: "Build", value: "1.50")], hidden: ["Locale"], renamed: ["Device": " Model "])
        var opened = taken
        EnvironmentCollector.applyFieldSettings(now, to: &opened, includingYourFields: false)
        check(opened.extras == taken.extras, "opening an old capture keeps its own field values", "\(String(describing: opened.extras))")
        check(opened.hiddenFields == ["Locale"] && opened.renamedFields == ["Device": "Model"], "opening an old capture applies the fields shown and their names")
        var edited = taken
        EnvironmentCollector.applyFieldSettings(now, to: &edited, includingYourFields: true)
        check(edited.extras == now.extras, "a field changed while the editor is open takes the new value")
    }

    /// The note of an arrow with text sits at the arrow's tail, on the side the arrow comes from,
    /// and a click on the note picks the mark.
    /// The URL is asked of the browser process the person looked at, by raw Apple event codes from
    /// Chromium's scripting dictionary; a wrong code would leave every URL empty.
    /// The marks of a clip saved before the fix (off the frame, a few microseconds long at the end)
    /// are put back on the frame and made visible when the clip opens.
    /// The copy button with its longest title fits the video editor's side panel (270 pt less its
    /// 16 pt padding); a wider one pushed the whole panel out of the window.
    /// `--clip-frame`: the preview frame of a saved clip with its marks, as the video editor builds it.
    static func clipFrame(folder: URL, seconds: Double, to output: URL) async -> Int32 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let captureData = try? Data(contentsOf: folder.appendingPathComponent("capture.json")), let capture = try? decoder.decode(Capture.self, from: captureData) else {
            print("no capture.json in \(folder.path)")
            return 1
        }
        var project = EditorMemory.newVideoProject(duration: capture.duration)
        if let data = try? Data(contentsOf: folder.appendingPathComponent("project.json")), let saved = try? JSONDecoder().decode(VideoProject.self, from: data) {
            project = saved.repairingMarks()
        }
        let asset = AVURLAsset(url: folder.appendingPathComponent("original.mp4"))
        do {
            let built = try await VideoCompositor.build(asset: asset, project: project, events: capture.events, environment: capture.environment)
            let generator = AVAssetImageGenerator(asset: built.composition)
            generator.videoComposition = built.videoComposition
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let time = CMTime(seconds: built.timeMap.outputTime(forSource: seconds), preferredTimescale: 600)
            let frame = try await generator.image(at: time).image
            ImageFiles.write(frame, to: output, type: "public.png")
            print("frame at \(seconds)s (output \(String(format: "%.2f", time.seconds))s), \(project.overlays.count) marks, render \(Int(built.renderSize.width))x\(Int(built.renderSize.height)) → \(output.path)")
            return 0
        } catch {
            print("could not build: \(error.localizedDescription)")
            return 1
        }
    }

    private static func checkCopyReportButtonFits() {
        let button = CopyReportButton(help: "", stepCount: 999) { _ in }
        let hosting = NSHostingView(rootView: button.environment(AppState.shared))
        let width = hosting.fittingSize.width
        check(width > 0 && width <= 270 - 32, "copy bug report button fits the video side panel", "\(Int(width)) pt")
    }

    private static func checkVideoMarkRepair() {
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

    private static func checkBrowserURLRequest() {
        check(EnvironmentCollector.fourCharCode("cwin") == 0x6377_696E && EnvironmentCollector.fourCharCode("URL ") == 0x5552_4C20, "browser URL request codes")
        // A process that is not there answers with an error, not a hang or a crash.
        let started = Date()
        let url = EnvironmentCollector.chromiumURL(pid: 999_999)
        check(url.isEmpty && Date().timeIntervalSince(started) < EnvironmentCollector.urlTimeout + 1, "browser URL request to a closed browser gives up quietly")
    }

    private static func checkArrowWithText() {
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

    private static func checkControlTreeCoordinates() {
        check(ControlTree.whole(12.7) == "12", "control tree: a coordinate is a whole number")
        check(ControlTree.whole(-3.5) == "-3", "control tree: a negative coordinate")
        check(ControlTree.whole(.nan) == "?", "control tree: a NaN coordinate shows as ?")
        check(ControlTree.whole(.infinity) == "?", "control tree: an infinite coordinate shows as ?")
        check(ControlTree.whole(1e300) == "?", "control tree: a coordinate too big for Int shows as ?")
    }

    private static func checkRegionPickerButtons() {
        final class Finished {
            var calls = 0
            var rect: CGRect?
        }
        let finished = Finished()
        let view = RegionSelectionView(frame: CGRect(x: 0, y: 0, width: 1200, height: 800))
        view.selection = CGRect(x: 300, y: 200, width: 400, height: 300)
        view.onFinish = { rect in
            finished.calls += 1
            finished.rect = rect
        }
        let window = NSWindow(contentRect: CGRect(x: -3000, y: -3000, width: 1200, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view

        var buttons: [String: DrawnButton] = [:]
        var labels: [String] = []
        for child in view.accessibilityChildren() ?? [] {
            guard let button = child as? DrawnButton else { continue }
            let label = button.accessibilityLabel() ?? ""
            labels.append(label)
            buttons[label] = button
        }
        let expected = ["Size 720p", "Size 1080p", "Size 1440×900", "Size 16:9", "Size 4:3", "Size 1:1", "Size Phone", "Size Full screen", "Cancel", "Record"]
        check(labels == expected, "the area picker names its buttons and size chips", labels.joined(separator: ", "))

        // Cancel is drawn 12 pt under the selection, left of its middle (flipped view, top-left origin).
        if let cancel = buttons["Cancel"] {
            let frame = cancel.accessibilityFrame()
            let expectedFrame = CGRect(x: -3000 + 500 - 114, y: -3000 + 800 - (500 + 12) - 32, width: 110, height: 32)
            check(frame == expectedFrame, "the picker's Cancel sits where it is drawn", "\(frame) vs \(expectedFrame)")
        }

        // VoiceOver keeps its place: asking again gives the same elements.
        let askedAgain = view.accessibilityChildren() ?? []
        var sameElements = askedAgain.count == labels.count
        for child in askedAgain {
            if let button = child as? DrawnButton, buttons[button.accessibilityLabel() ?? ""] !== button {
                sameElements = false
            }
        }
        check(sameElements, "the area picker keeps its accessibility elements between questions")
        let cancelBefore = buttons["Cancel"]?.accessibilityFrame() ?? .zero
        if let cancel = buttons["Cancel"] {
            let found = view.accessibilityHitTest(CGPoint(x: cancelBefore.midX, y: cancelBefore.midY)) as? DrawnButton
            check(found === cancel, "VoiceOver's pointer finds the picker's Cancel", "\(String(describing: found?.accessibilityLabel()))")
        }

        _ = buttons["Size Full screen"]?.accessibilityPerformPress()
        check(view.selection == view.bounds && finished.calls == 0, "pressing a size chip resizes the area", "\(view.selection)")
        // The selection grew, so Cancel moved down to the bottom edge; the same element says so.
        let cancelAfter = buttons["Cancel"]?.accessibilityFrame() ?? .zero
        let expectedAfter = CGRect(x: -3000 + 600 - 114, y: -3000 + 800 - (800 - 44) - 32, width: 110, height: 32)
        check(cancelAfter == expectedAfter, "the picker's Cancel frame follows the selection", "\(cancelAfter) vs \(expectedAfter)")
        _ = buttons["Record"]?.accessibilityPerformPress()
        check(finished.calls == 1 && finished.rect == view.bounds, "pressing Record records the area", "\(finished.calls) \(String(describing: finished.rect))")
        _ = buttons["Cancel"]?.accessibilityPerformPress()
        check(finished.calls == 2 && finished.rect == nil, "pressing Cancel cancels", "\(finished.calls) \(String(describing: finished.rect))")

        // The scrolling screenshot picker has no sizes and says Capture.
        view.showsSizes = false
        view.confirmTitle = "Capture  ↩"
        var scrollingLabels: [String] = []
        for child in view.accessibilityChildren() ?? [] {
            if let button = child as? DrawnButton {
                scrollingLabels.append(button.accessibilityLabel() ?? "")
            }
        }
        check(scrollingLabels == ["Cancel", "Capture"], "the scrolling screenshot picker shows Cancel and Capture", scrollingLabels.joined(separator: ", "))
    }

    /// A new screenshot or clip opens the way the last one was left; an older capture keeps its own
    /// badge and does not change what new ones get. Runs on scratch defaults and folders.
    private static func checkEditorMemory() async {
        let domain = "bugbear.selftest.memory.\(UUID().uuidString)"
        guard let scratch = UserDefaults(suiteName: domain) else {
            check(false, "editor memory: scratch defaults")
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bugbear-memory-\(UUID().uuidString)", isDirectory: true)
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

    private static func checkDefaultMarkSize() {
        check(StrokeSize.thick.width == 7 && LiveOverlay().stroke == .thick, "drawing on the screen starts at size 7")
    }

    /// While tests record, buttons that hand something to macOS only say what they would open.
    private static func checkSystemActionsRecord() {
        SystemActions.startRecording()
        SystemActions.open(URL(fileURLWithPath: "/tmp/bugbear-captures"))
        SystemActions.askPermission("Accessibility") {
            check(false, "a recorded permission prompt is not shown")
        }
        let loginWorked = (try? SystemActions.setOpenAtLogin(true)) != nil
        let chosen = SystemActions.chooseFolder(startingAt: URL(fileURLWithPath: "/tmp"))
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("bugbear-trash-\(UUID().uuidString).bin")
        FileManager.default.createFile(atPath: kept.path, contents: Data([1]))
        defer { try? FileManager.default.removeItem(at: kept) }
        let trashWorked = (try? SystemActions.trash(kept)) != nil
        let recorded = SystemActions.recorded
        SystemActions.stopRecording()
        check(recorded == ["open /tmp/bugbear-captures", "ask Accessibility", "login true", "choose folder /tmp", "trash \(kept.path)"] && loginWorked && chosen == nil, "buttons that open macOS things are recorded in tests, not opened", recorded.joined(separator: " | "))
        check(trashWorked && FileManager.default.fileExists(atPath: kept.path), "a file moved to the Trash in tests stays where it is")
        checkAllowShowsOneWindow()
    }

    /// The grip that moves the recording area sits above the frame, clear of the top handle, and
    /// just inside when the area reaches the top of the screen.
    private static func checkAreaGrip() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let size = AreaHandleView.gripSize
        let area = CGRect(x: 400, y: 300, width: 640, height: 360)
        let above = CGRect(origin: RecordingOutline.gripOrigin(area: area, screens: [screen]), size: size)
        let topHandle = CGRect(x: area.midX - AreaHandleView.side / 2, y: area.maxY - AreaHandleView.side / 2, width: AreaHandleView.side, height: AreaHandleView.side)
        check(above.minY > area.maxY && !above.intersects(topHandle) && abs(above.midX - area.midX) < 1, "the grip sits centered above the recording frame, clear of the top handle", "\(above)")
        let atTop = CGRect(x: 400, y: 600, width: 640, height: 382)
        let inside = CGRect(origin: RecordingOutline.gripOrigin(area: atTop, screens: [screen]), size: size)
        check(screen.contains(inside) && inside.maxY < atTop.maxY - AreaHandleView.side / 2, "with no room above, the grip sits inside the frame and stays on the screen", "\(inside)")

        // The picker (flipped, top-left) has the same grip, clear of the size bar at the top.
        let picked = CGRect(x: 400, y: 300, width: 640, height: 360)
        let pickerGrip = RegionSelectionView.gripRect(area: picked, screens: [screen], avoiding: nil, handleSize: 12)
        // A press within reach of the top handle resizes, so the grip stays out of that reach.
        let topReach = CGRect(x: picked.midX - 12, y: picked.minY - 12, width: 24, height: 24)
        check(pickerGrip.maxY < picked.minY && !pickerGrip.intersects(topReach) && abs(pickerGrip.midX - picked.midX) < 1, "the picker's grip sits centered above the area, out of the top handle's reach", "\(pickerGrip)")
        let bar = CGRect(x: 300, y: 42, width: 900, height: 40)
        let underBar = RegionSelectionView.gripRect(area: CGRect(x: 400, y: 100, width: 640, height: 360), screens: [screen], avoiding: bar, handleSize: 12)
        check(!underBar.intersects(bar) && underBar.minY > 100 + 12, "with the size bar in the way, the picker's grip goes inside the area, out of the top handle's reach", "\(underBar)")
        let screenTop = RegionSelectionView.gripRect(area: CGRect(x: 0, y: 0, width: 640, height: 360), screens: [screen], avoiding: nil, handleSize: 12)
        check(screenTop.minY > 12, "at the top of the screen the picker's grip goes inside the area", "\(screenTop)")
        let picker = RegionSelectionView(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        picker.selection = CGRect(x: 400, y: 300, width: 640, height: 0)
        let flat = picker.hasGrip
        picker.selection = picked
        check(!flat && picker.hasGrip, "the picker has a grip only for an area that is there, not a flat one being drawn")
        let scrolling = RegionSelectionView(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        scrolling.showsSizes = false
        check(scrolling.model.barRect == nil, "a picker without the size bar has no bar for the grip to avoid")
        checkAreaAcrossScreens()
    }

    /// The picker's screens share one area: it can lie across two of them.
    private static func checkAreaAcrossScreens() {
        // Desktop points (y down from the top of the first screen): a laptop and a taller monitor to
        // its right whose top is 200 pt higher.
        let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let monitor = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let model = RegionPickerModel(selection: CGRect(x: 1300, y: 300, width: 640, height: 360), screens: [laptop, monitor])
        let left = RegionSelectionView.screen(of: model, frame: laptop, pixelScale: 2, confirmTitle: "Record", showsSizes: true)
        let right = RegionSelectionView.screen(of: model, frame: monitor, pixelScale: 1, confirmTitle: "Record", showsSizes: false)
        // The grip keeps clear of the size bar that is drawn: the laptop's, not one the monitor never shows.
        check(model.barRect.map { bar in laptop.contains(bar) } == true, "the grip keeps clear of the size bar on the picker's first screen only", "\(String(describing: model.barRect))")
        check(model.clipScale(of: model.selection) == 2 && model.clipScale(of: CGRect(x: 2000, y: 100, width: 100, height: 100)) == 1, "an area's density is the sharpest screen it is on")
        check(model.labelScreen == laptop, "the size label is on the screen with the area's top-left corner")
        check(left.selection == CGRect(x: 1300, y: 300, width: 640, height: 360) && right.selection == CGRect(x: -212, y: 500, width: 640, height: 360), "each screen of the picker shows the same area in its own place", "\(left.selection) / \(right.selection)")
        right.selection = CGRect(x: 100, y: 100, width: 640, height: 360)
        check(model.selection == CGRect(x: 1612, y: -100, width: 640, height: 360) && left.selection.minX == 1612, "an area moved on one screen moves on the others")
        check(model.mainScreen == monitor, "the monitor holds most of an area on it")
        // Above the monitor's part of the desktop that the laptop does not reach, the grip has room.
        check(model.gripRect.maxY < model.selection.minY, "the grip stays above an area near the top of the taller screen", "\(model.gripRect)")
        model.selection = CGRect(x: 1300, y: 300, width: 640, height: 360)
        let buttons = model.buttonRects
        check(monitor.contains(buttons.cancel) && monitor.contains(buttons.record), "Cancel and Record go on the screen under the area's bottom middle", "\(buttons)")
        // The monitor ends at 880 and the laptop at 982: below the monitor's bottom there is no screen.
        check(model.touchesAScreen(CGRect(x: 1400, y: 900, width: 50, height: 50)) && !model.touchesAScreen(CGRect(x: 2000, y: 900, width: 50, height: 50)), "the corner under the monitor, beside the laptop that reaches lower, is no screen")
        check(model.reach == CGRect(x: 0, y: -200, width: 3432, height: 1182), "the area can go anywhere on both screens")
        // Global points: the frame's top (1160) is above the laptop's (982) but the monitor goes on to 1280.
        let grip = RecordingOutline.gripOrigin(area: CGRect(x: 1600, y: 800, width: 640, height: 360), screens: [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 1920, height: 1280)])
        check(grip.y > 1160, "while recording the grip goes above the frame where the taller screen has room", "\(grip)")
    }

    /// Allow… asks macOS (its window has Open System Settings) or opens System Settings, never both.
    private static func checkAllowShowsOneWindow() {
        let suite = "bugbear.selftest.permissions.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            check(false, "a settings store for the Allow check")
            return
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        SystemActions.startRecording()
        SystemActions.askOnceThenOpenSettings("Screen Recording", pane: "Privacy_ScreenCapture", defaults: defaults) {
            check(false, "a recorded permission prompt is not shown")
        }
        let first = SystemActions.recorded
        SystemActions.askOnceThenOpenSettings("Screen Recording", pane: "Privacy_ScreenCapture", defaults: defaults) {
            check(false, "a recorded permission prompt is not shown")
        }
        let second = Array(SystemActions.recorded.dropFirst(first.count))
        let afterGuide = UserDefaults(suiteName: suite + ".guide")
        defer { afterGuide?.removePersistentDomain(forName: suite + ".guide") }
        let countBefore = SystemActions.recorded.count
        if let fresh = afterGuide {
            SystemActions.askOnceThenOpenSettings("Screen Recording", pane: "Privacy_ScreenCapture", askedBefore: true, defaults: fresh) {
                check(false, "a recorded permission prompt is not shown")
            }
        }
        let asked = Array(SystemActions.recorded.dropFirst(countBefore))
        SystemActions.stopRecording()
        check(asked == ["open x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"], "Allow after something else asked already opens System Settings at once", asked.joined(separator: " | "))
        check(first == ["ask Screen Recording"], "the first Allow only asks macOS, without opening System Settings too", first.joined(separator: " | "))
        check(second == ["open x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"], "a later Allow opens System Settings, without asking macOS again", second.joined(separator: " | "))
    }

    /// A card's "More actions" menu offers the log and crash report only when they were saved.
    private static func checkHistoryCardMenu() {
        let capture = Capture(id: UUID(), kind: .video, createdAt: Date(), environment: EnvironmentSnapshot(), duration: 10, events: [])
        defer { try? FileManager.default.removeItem(at: capture.folder) }
        let plain = HistoryCardAction.available(for: capture)
        check(plain == [.open, .reveal, .copyMarkdown, .copyJira, .copyEnvironment, .delete], "a capture card menu without a log or crash report", "\(plain)")
        try? FileManager.default.createDirectory(at: capture.folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: capture.systemLogURL.path, contents: Data("log".utf8))
        FileManager.default.createFile(atPath: capture.crashReportURL.path, contents: Data("crash".utf8))
        let crash = HistoryCardAction.available(for: capture)
        check(crash == HistoryCardAction.allCases && crash.last == .delete, "a crash clip card menu opens its log and crash report, Delete stays last", "\(crash)")
    }

    /// A clip's system log is written seconds after its editor opens; the editor still has to show
    /// the "System log" button once it is there.
    private static func checkLateSystemLog() {
        let capture = Capture(id: UUID(), kind: .video, createdAt: Date(), environment: EnvironmentSnapshot(), duration: 10, events: [])
        defer { try? FileManager.default.removeItem(at: capture.folder) }
        let store = CaptureStore.shared
        final class Changed {
            var value = false
        }
        let changed = Changed()
        let before = withObservationTracking {
            store.hasSystemLog(capture)
        } onChange: {
            changed.value = true
        }
        try? FileManager.default.createDirectory(at: capture.folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: capture.systemLogURL.path, contents: Data("log".utf8))
        store.systemLogSaved(for: capture.id)
        check(!before && changed.value && store.hasSystemLog(capture), "an open editor learns about a system log saved after it opened", "before=\(before) changed=\(changed.value)")
    }

    /// Scratch settings domains this run made, to check they are gone at the end.
    private static var scratchDomains: [String] = []

    static func preferencesFile(_ domain: String) -> URL {
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Preferences/\(domain).plist")
    }

    /// Empties a scratch settings domain; its file is deleted at the end of the run. Removing the
    /// domain alone leaves an empty .plist in ~/Library/Preferences, one more after every run.
    static func forgetScratchDefaults(_ defaults: UserDefaults, domain: String) {
        defaults.removePersistentDomain(forName: domain)
        if !scratchDomains.contains(domain) {
            scratchDomains.append(domain)
        }
    }

    private static func checkCrashClipMigration() {
        let domain = "bugbear.selftest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: domain) else {
            check(false, "crash clip migration: scratch defaults")
            return
        }
        defer { forgetScratchDefaults(defaults, domain: domain) }
        defaults.register(defaults: ["keepCrashClipsDays": 7])
        let days = { defaults.integer(forKey: "keepCrashClipsDays") }

        // Used Bugbear up to 0.8.1, then updated.
        defaults.set(true, forKey: "onboardingCompleted")
        defaults.set(AppSettings.crashClipSettingReleaseID - 1, forKey: "whatsNewLastSeenID")
        AppSettings.keepCrashClipsForEarlierUsers(defaults, domain: domain)
        check(days() == 0, "an earlier user keeps all crash clips", "\(days())")

        defaults.set(30, forKey: "keepCrashClipsDays")
        AppSettings.keepCrashClipsForEarlierUsers(defaults, domain: domain)
        check(days() == 30, "a chosen crash clip time stays", "\(days())")

        // Went through the guide in 0.9.0 or later and left 7 days as they were.
        defaults.removeObject(forKey: "keepCrashClipsDays")
        defaults.set(AppSettings.crashClipSettingReleaseID, forKey: "whatsNewLastSeenID")
        AppSettings.keepCrashClipsForEarlierUsers(defaults, domain: domain)
        check(days() == 7, "someone who kept the guide's 7 days keeps 7 days", "\(days())")

        // A new install before the guide is finished.
        defaults.removeObject(forKey: "onboardingCompleted")
        defaults.removeObject(forKey: "whatsNewLastSeenID")
        AppSettings.keepCrashClipsForEarlierUsers(defaults, domain: domain)
        check(days() == 7, "a new install starts at 7 days", "\(days())")

        // No bundle id (a bare build): nothing is changed.
        defaults.set(true, forKey: "onboardingCompleted")
        defaults.set(1, forKey: "whatsNewLastSeenID")
        AppSettings.keepCrashClipsForEarlierUsers(defaults, domain: "")
        check(days() == 7, "without a bundle id the setting is left alone", "\(days())")
    }

    /// Typing never reaches a clip: letters, ⇧ letters and ⌥ characters are masked, shortcuts and
    /// special keys are shown.
    private static func checkKeyLabels() {
        let typing = InputEventRecorder.typingLabel
        let cases: [(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String, expected: String)] = [
            (keyCode: 0, flags: [], characters: "a", expected: typing),
            (keyCode: 0, flags: [.shift], characters: "A", expected: typing),
            (keyCode: 19, flags: [.option], characters: "2", expected: typing),
            (keyCode: 19, flags: [.option, .shift], characters: "@", expected: typing),
            (keyCode: 8, flags: [.command], characters: "c", expected: "⌘ C"),
            // A Russian layout types "с" on the C key: the shortcut is still ⌘C.
            (keyCode: 8, flags: [.command], characters: "с", expected: "⌘ C"),
            (keyCode: 18, flags: [.option, .shift, .command], characters: "!", expected: "⌥⇧⌘ 1"),
            (keyCode: 0, flags: [.control], characters: "a", expected: "⌃ A"),
            (keyCode: 36, flags: [], characters: "\r", expected: "Enter"),
            (keyCode: 48, flags: [.shift], characters: "\t", expected: "⇧ Tab"),
            (keyCode: 53, flags: [], characters: "", expected: "Esc"),
            // Moving by words is navigation, not typing.
            (keyCode: 123, flags: [.option], characters: "", expected: "⌥ ←"),
            (keyCode: 51, flags: [.option], characters: "", expected: "⌥ Delete"),
        ]
        for item in cases {
            let label = InputEventRecorder.label(keyCode: item.keyCode, flags: item.flags, characters: item.characters)
            check(label == item.expected, "key code \(item.keyCode) with flags \(item.flags.rawValue) shows \(item.expected)", label)
        }
    }

    /// capture.json and project.json written by the first version still load. A new field that is
    /// not optional breaks this: synthesized Codable ignores default values when decoding, so old
    /// files would fail, the capture would vanish from History and the video edits would be lost.
    private static func checkFirstVersionFiles() {
        let capture = """
        {"id": "7C1E3B5A-1D2E-4F60-9A7B-1C2D3E4F5A6B", "kind": "video", "createdAt": 783000000, "duration": 12.5,
         "environment": {"osVersion": "14.5", "osBuild": "23F79", "deviceModel": "Mac14,2", "display": "1512x982 @2x",
           "appName": "Safari", "appVersion": "17.5", "appBundleId": "com.apple.Safari", "url": "https://example.com",
           "locale": "en_US", "timeZone": "Europe/Lisbon", "appearance": "Dark", "capturedAt": 783000000},
         "events": [{"kind": "click", "time": 1.5, "x": 100, "y": 200, "label": "Click", "target": "Button Save", "app": "Safari"},
                    {"kind": "key", "time": 2, "x": 0, "y": 0, "label": "⌘ C"}]}
        """
        let decodedCapture = try? JSONDecoder().decode(Capture.self, from: Data(capture.utf8))
        check(decodedCapture?.events.count == 2 && decodedCapture?.screens == nil, "a capture.json from the first version loads")

        let video = """
        {"timeline": {"sourceDuration": 20, "trim": {"start": 1, "end": 19}, "cuts": [{"start": 5, "end": 6}],
           "speeds": [{"span": {"start": 8, "end": 10}, "factor": 0.5}], "freezes": [{"at": 12, "duration": 2}], "frameDuration": 0.0333},
         "overlays": [{"id": "1C2D3E4F-5A6B-4C7D-8E9F-0A1B2C3D4E5F", "kind": "arrow", "span": {"start": 2, "end": 4},
           "start": [10, 20], "end": [30, 40], "text": "", "color": "coral"}],
         "showClicks": true, "showKeys": false, "showBadge": true, "badgeCorner": "bottomLeft",
         "format": "GIF", "quality": "720p", "gifFramesPerSecond": 10}
        """
        let decodedVideo = try? JSONDecoder().decode(VideoProject.self, from: Data(video.utf8))
        check(decodedVideo?.timeline.cuts.count == 1 && decodedVideo?.format == .gif && decodedVideo?.overlays.count == 1 && decodedVideo?.sizeLimitMB == nil, "a video project.json from the first version keeps its edits")

        let screenshot = """
        {"annotations": [{"id": "2C2D3E4F-5A6B-4C7D-8E9F-0A1B2C3D4E5F", "tool": "rectangle", "start": [10, 10], "end": [90, 60],
           "points": [], "text": "", "number": 0, "color": "blue", "lineWidth": 4, "fontSize": 24},
          {"id": "3C2D3E4F-5A6B-4C7D-8E9F-0A1B2C3D4E5F", "tool": "text", "start": [20, 20], "end": [20, 20],
           "points": [], "text": "Bug here", "number": 0, "color": "coral", "lineWidth": 4, "fontSize": 28}],
         "crop": [[0, 0], [400, 300]], "showBadge": false, "badgeCorner": "topRight", "hasCombinedBase": false}
        """
        let decodedScreenshot = try? JSONDecoder().decode(ScreenshotDocument.Project.self, from: Data(screenshot.utf8))
        let marks = decodedScreenshot?.annotations ?? []
        check(marks.count == 2 && marks.first?.isFilled == false && marks.last?.hasClearBackground == false, "a screenshot project.json from the first version keeps its marks")
    }

    /// A report copied from the video editor lists what is still in the edited video, at the
    /// edited times: actions in a cut part are dropped and later ones move up.
    private static func checkReportFollowsEdits() {
        var events: [InputEvent] = []
        events.append(InputEvent(kind: .click, time: 1, x: 0.5, y: 0.5, label: "", target: "\"Before\" button", app: "Chrome"))
        events.append(InputEvent(kind: .click, time: 5.5, x: 0.5, y: 0.5, label: "", target: "\"Cut\" button", app: "Chrome"))
        events.append(InputEvent(kind: .click, time: 9, x: 0.5, y: 0.5, label: "", target: "\"After\" button", app: "Chrome"))
        let capture = Capture(id: UUID(), kind: .video, createdAt: Date(), environment: EnvironmentSnapshot(), duration: 10, events: events)
        var timeline = EditTimeline(sourceDuration: 10)
        timeline.cuts = [TimeSpan(start: 5, end: 6)]
        let map = TimeMap(pieces: timeline.pieces())
        let report = BugReportBuilder.markdown(for: capture, timeMap: map)
        check(report.contains("Before") && report.contains("After"), "the report keeps actions outside the cut", report)
        check(!report.contains("\"Cut\""), "the report drops actions in a cut part", report)
        // Steps carry no times in the text; the times still follow the edit for the video captions.
        let edited = BugReportBuilder.actions(for: events, timeMap: map)
        check(edited.count == 2 && abs((edited.last?.time ?? 0) - 8) < 0.01, "later actions move up by the cut length", "\(edited.count)")
        let unedited = BugReportBuilder.markdown(for: capture, timeMap: nil)
        check(unedited.contains("\"Cut\""), "without edits every action stays", unedited)
    }

    /// Saving never overwrites a file, and a shortcut turned off stays off after a restart.
    private static func checkSavedNamesAndShortcuts() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bugbear-names-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = AppPaths.uniqueURL(in: folder, name: "Bugbear shot", ext: "png")
        FileManager.default.createFile(atPath: first.path, contents: Data([1]))
        let second = AppPaths.uniqueURL(in: folder, name: "Bugbear shot", ext: "png")
        FileManager.default.createFile(atPath: second.path, contents: Data([2]))
        let third = AppPaths.uniqueURL(in: folder, name: "Bugbear shot", ext: "png")
        check(first.lastPathComponent == "Bugbear shot.png" && second.lastPathComponent == "Bugbear shot 2.png" && third.lastPathComponent == "Bugbear shot 3.png", "a saved file never overwrites another", "\(first.lastPathComponent) \(second.lastPathComponent) \(third.lastPathComponent)")

        let custom = Shortcut(keyCode: 46, modifiers: 2560, key: "M")
        var overrides: [String: Shortcut?] = [:]
        overrides[HotKeyAction.saveShort.rawValue] = .some(nil)
        overrides[HotKeyAction.saveMinute.rawValue] = .some(custom)
        let restored = HotKeySettings.decode(HotKeySettings.encode(overrides) ?? Data())
        let turnedOff = restored[HotKeyAction.saveShort.rawValue]
        check(turnedOff != nil && turnedOff! == nil, "a shortcut turned off stays off after a restart")
        check(restored[HotKeyAction.saveMinute.rawValue] == .some(custom), "a changed shortcut survives a restart")
        check(restored[HotKeyAction.saveBuffer.rawValue] == nil, "an untouched shortcut keeps its default")
    }

    /// Video captions follow the report steps: one per step, shown until the next step, never wider
    /// than the frame. The playhead can be grabbed a little around its line.
    private static func checkStepCaptions() {
        var events: [InputEvent] = []
        events.append(InputEvent(kind: .click, time: 1, x: 0.5, y: 0.5, label: "", target: "\"Email\" text field", app: "Chrome", url: "https://shop.test/login"))
        var typing = InputEvent(kind: .key, time: 3, x: 0, y: 0, label: InputEventRecorder.typingLabel, target: "\"Email\" text field", app: "Chrome")
        typing.text = "john@test.com"
        events.append(typing)
        let longPage = "https://shop.test/" + String(repeating: "very-long-path/", count: 30)
        events.append(InputEvent(kind: .click, time: 10, x: 0.5, y: 0.5, label: "", target: "\"Pay\" button", app: "Chrome", url: longPage))
        let size = CGSize(width: 1280, height: 720)
        let captions = VideoCompositor.stepCaptions(events: events, timeMap: nil, renderSize: size, unit: 1)
        // Open shop.test/login, Click Email, Type, Open long page, Click Pay.
        check(captions.count == 5, "one caption per step, pages included", "\(captions.count)")
        if captions.count == 5 {
            check(captions[1].start == 1 && captions[1].end == 3, "a caption stays until the next step", "\(captions[1].start)-\(captions[1].end)")
            check(captions[2].end == 3 + VideoCompositor.stepCaptionLongest, "a caption leaves after a while when nothing follows soon", "\(captions[2].end)")
            var fits = true
            for caption in captions where caption.image.extent.maxX > size.width || caption.image.extent.minX < 0 {
                fits = false
            }
            check(fits, "a long page address does not run off the frame")
        }
        // With the first click cut out, the video numbers its steps like the copied report.
        var timeline = EditTimeline(sourceDuration: 12)
        timeline.cuts = [TimeSpan(start: 0.5, end: 1.5)]
        let edited = VideoCompositor.stepCaptions(events: events, timeMap: TimeMap(pieces: timeline.pieces()), renderSize: size, unit: 1)
        let report = BugReport.stepLines(from: BugReportBuilder.actions(for: events, timeMap: TimeMap(pieces: timeline.pieces())))
        check(edited.count == report.count && edited.count == 3, "captions leave out steps in a cut, like the report", "\(edited.count) vs \(report.count)")
    }

    /// The recording bar's clock shows the state and time, and redraws only when they change: a
    /// redraw of anything on screen is a frame the capture has to deal with.
    private static func checkRecordingClock() {
        let session = RecordingSession()
        let clock = RecordingClockView(session: session)
        // A clock that moves only when the check says so.
        var moment = session.startTime + 0.1
        clock.now = { moment }
        check(clock.currentText == "REC 0:00 on", "the recording clock shows REC and the time", clock.currentText)
        check(clock.needsRedraw, "a new clock wants to be drawn")
        if let bitmap = clock.bitmapImageRepForCachingDisplay(in: clock.bounds) {
            clock.cacheDisplay(in: clock.bounds, to: bitmap)
        }
        check(clock.drawCount == 1 && !clock.needsRedraw, "the clock drew once and has nothing new", "draws \(clock.drawCount)")
        // Ticks within the same second and blink phase change nothing.
        moment = session.startTime + 0.5
        check(!clock.needsRedraw, "the recording clock does not redraw when nothing changed", clock.currentText)
        moment = session.startTime + 0.9
        check(clock.needsRedraw && clock.currentText == "REC 0:00 off", "the recording dot blinks", clock.currentText)
        moment = session.startTime + 1.3
        check(clock.needsRedraw && clock.currentText == "REC 0:01 on", "the recording clock redraws for a new second", clock.currentText)
        session.pause()
        check(clock.needsRedraw && clock.currentText.hasPrefix("Paused"), "the recording clock redraws when paused", clock.currentText)
        check(clock.accessibilityLabel()?.hasPrefix("Paused, ") == true, "VoiceOver reads the recording clock", clock.accessibilityLabel() ?? "")
    }

    /// A fake Bugbear crash report: the header line and the body macOS writes.
    static func fakeCrashReport(bundleId: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        let header = "{\"app_name\":\"Bugbear\",\"timestamp\":\"\(formatter.string(from: date))\",\"bug_type\":\"309\",\"bundleID\":\"\(bundleId)\",\"name\":\"Bugbear\"}"
        let body = """
        {"exception":{"type":"EXC_BREAKPOINT","signal":"SIGTRAP"},"termination":{"indicator":"Trace/BPT trap: 5"},
         "asi":{"libswiftCore.dylib":["Fatal error: Index out of range in \(Feedback.homePath)/Code"]},
         "faultingThread":0,"usedImages":[{"name":"libswiftCore.dylib"},{"name":"Bugbear"}],
         "threads":[{"triggered":true,"frames":[{"imageIndex":0,"symbol":"_assertionFailure"},{"imageIndex":1,"symbol":"CaptureStore.selectScreen(_:)"}]}]}
        """
        return header + "\n" + body
    }

    /// A problem report hides the home folder and user name in its text and its zip, keeps the
    /// version, packs only recent Bugbear crash reports, and a new crash is found on the next launch.
    private static func checkFeedback(folder: URL) {
        let model = FeedbackModel(kind: .problem)
        model.details = "It broke"
        let report = model.report
        let versionLine = report.environment.first { field in field.name == "Bugbear" }
        check(versionLine?.value.hasPrefix(Updater.shared.version) == true, "a problem report names the Bugbear version", "\(String(describing: versionLine))")
        check(Feedback.redact("open \(Feedback.homePath)/Desktop as \(NSUserName())") == "open ~/Desktop as <user>", "a report hides the home folder and the user name")

        let bundleId = "com.example.bugbear-check"
        let crashFolder = folder.appendingPathComponent("feedback-crashes", isDirectory: true)
        try? FileManager.default.removeItem(at: crashFolder)
        try? FileManager.default.createDirectory(at: crashFolder, withIntermediateDirectories: true)
        let recent = crashFolder.appendingPathComponent("Bugbear-2026-10-25-120000.ips")
        let old = crashFolder.appendingPathComponent("Bugbear-2026-09-01-120000.ips")
        try? Data(fakeCrashReport(bundleId: bundleId).utf8).write(to: recent)
        try? Data("old crash".utf8).write(to: old)
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-20 * 24 * 3600)], ofItemAtPath: old.path)
        try? Data("other app".utf8).write(to: crashFolder.appendingPathComponent("Safari-2026-10-25-120000.ips"))

        let zipFolder = folder.appendingPathComponent("feedback-zip", isDirectory: true)
        try? FileManager.default.removeItem(at: zipFolder)
        let environment = "Bugbear: test\nHome: \(Feedback.homePath)"
        guard case .success(let archive) = Feedback.makeLogArchive(environmentText: environment, in: zipFolder, crashFolder: crashFolder) else {
            check(false, "the log zip is made")
            return
        }
        let unpacked = zipFolder.appendingPathComponent("unpacked", isDirectory: true)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-x", "-k", archive.path, unpacked.path]
        try? task.run()
        task.waitUntilExit()
        check(task.terminationStatus == 0, "the log zip unpacks")
        let inner = unpacked.appendingPathComponent("Bugbear logs", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: inner.path)) ?? []
        check(names.contains("environment.txt") && names.contains(recent.lastPathComponent) && !names.contains(old.lastPathComponent) && !names.contains("Safari-2026-10-25-120000.ips"), "the log zip has the environment and only recent Bugbear crash reports", "\(names)")
        var leaks: [String] = []
        for name in names {
            let text = (try? String(contentsOf: inner.appendingPathComponent(name), encoding: .utf8)) ?? ""
            if text.contains(Feedback.homePath) || text.range(of: "(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: NSUserName()) + "(?![A-Za-z0-9])", options: [.regularExpression, .caseInsensitive]) != nil {
                leaks.append(name)
            }
        }
        check(leaks.isEmpty, "files in the log zip hide the home folder and the user name", "\(leaks)")

        // The crash found on the next launch, and what goes into the issue about it.
        let defaults = UserDefaults(suiteName: "bugbear-feedback-check") ?? .standard
        defaults.removeObject(forKey: Feedback.lastCrashCheckKey)
        check(Feedback.crashSinceLastCheck(in: crashFolder, defaults: defaults, bundleId: bundleId) == nil, "the first launch does not bring up old crashes")
        check(defaults.object(forKey: Feedback.lastCrashCheckKey) is Date, "the first launch remembers when it looked")
        defaults.set(Date().addingTimeInterval(-60), forKey: Feedback.lastCrashCheckKey)
        let found = Feedback.crashSinceLastCheck(in: crashFolder, defaults: defaults, bundleId: bundleId)
        check(found?.lastPathComponent == recent.lastPathComponent, "a Bugbear crash since the last launch is found", "\(String(describing: found))")
        check(Feedback.crashSinceLastCheck(in: crashFolder, defaults: defaults, bundleId: bundleId) == nil, "the same crash is offered only once")

        // What must not count: another Bugbear build, a hang, a kill from outside, an older crash, junk.
        let others = folder.appendingPathComponent("feedback-not-crashes", isDirectory: true)
        try? FileManager.default.removeItem(at: others)
        try? FileManager.default.createDirectory(at: others, withIntermediateDirectories: true)
        try? Data(fakeCrashReport(bundleId: "io.github.other.bugbear").utf8).write(to: others.appendingPathComponent("Bugbear-other-build.ips"))
        let hang = fakeCrashReport(bundleId: bundleId).replacingOccurrences(of: "\"bug_type\":\"309\"", with: "\"bug_type\":\"288\"")
        try? Data(hang.utf8).write(to: others.appendingPathComponent("Bugbear-hang.ips"))
        let killed = fakeCrashReport(bundleId: bundleId).replacingOccurrences(of: "\"termination\":{\"indicator\":\"Trace/BPT trap: 5\"}", with: "\"termination\":{\"namespace\":\"CODESIGNING\",\"indicator\":\"Invalid Page\"}")
        try? Data(killed.utf8).write(to: others.appendingPathComponent("Bugbear-codesigning.ips"))
        try? Data("not a report".utf8).write(to: others.appendingPathComponent("Bugbear-junk.ips"))
        let older = others.appendingPathComponent("Bugbear-older.ips")
        try? Data(fakeCrashReport(bundleId: bundleId).utf8).write(to: older)
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: older.path)
        defaults.set(Date().addingTimeInterval(-60), forKey: Feedback.lastCrashCheckKey)
        let wrong = Feedback.crashSinceLastCheck(in: others, defaults: defaults, bundleId: bundleId)
        check(wrong == nil, "other builds, hangs, kills from outside, older crashes and junk are not offered", "\(String(describing: wrong))")
        check(Feedback.crashSinceLastCheck(in: crashFolder, defaults: defaults, bundleId: "") == nil, "a build without a bundle id offers nothing")

        let crashText = Feedback.crashText(from: recent)
        check(crashText.contains("EXC_BREAKPOINT (SIGTRAP)") && crashText.contains("Fatal error: Index out of range in ~/Code") && crashText.contains("Bugbear  CaptureStore.selectScreen(_:)"), "the crash text has the reason, the message and the crashed thread, without the home folder", crashText)
        let scrubbed = Feedback.scrubIdentifiers("{\"crashReporterKey\" : \"ABC-123\",\"userID\":501,\"name\":\"Bugbear\"}")
        check(scrubbed == "{\"crashReporterKey\":\"<hidden>\",\"userID\":\"<hidden>\",\"name\":\"Bugbear\"}", "crash reports in the zip hide the Mac's ids", scrubbed)
        let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)["offerCrashReports"] as? Bool
        check(registered == true, "crash reports are offered by default")
        forgetScratchDefaults(defaults, domain: "bugbear-feedback-check")
    }

    /// A picture placed on a screenshot is drawn in its frame, on top of the screenshot.
    private static func checkPlacedImage(folder: URL) {
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

    /// A long tooltip wraps and its panel is tall enough for every line.
    private static func checkTooltipSize(folder: URL) {
        let text = "No fill: text without a label behind it, shapes as outlines only. Pick Text, Rectangle or Ellipse to use it"
        let layout = HoverTip.layout(for: text)
        let view = HoverTipView(text: text, textWidth: layout.textWidth)
        let needed = NSHostingView(rootView: Text(text).font(.system(size: HoverTip.fontSize)).frame(width: layout.textWidth, alignment: .leading).fixedSize(horizontal: false, vertical: true)).fittingSize
        check(layout.size.width <= HoverTip.maxTextWidth + 40, "a long tooltip wraps instead of growing wide", "\(layout.size)")
        check(needed.height + HoverTip.verticalPadding * 2 <= layout.size.height + 1, "a long tooltip has room for every line", "needs \(needed.height), panel \(layout.size.height)")
        render(view, size: layout.size, to: folder.appendingPathComponent("tooltip-long.png"))
    }

    /// Instructions say the keys in words, not only as symbols.
    private static func checkShortcutWords() {
        let shortcut = Shortcut.optionShift(18, "1")
        check(shortcut.spoken == "Option + Shift + 1", "shortcut in words", shortcut.spoken)
    }

    /// A filled rectangle tints what is inside it; an outline one leaves it as it was.
    private static func checkShapeFill() {
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
    private static func checkScreenshotFormats() {
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
    private static func checkAnnotationColors() {
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
        checkWhatsNewPictures()
        checkLocalization(folder: folder)
        checkPlayerView()
        checkCrashClipMigration()
        checkDefaultMarkSize()
        checkSystemActionsRecord()
        checkAreaGrip()
        checkHistoryCardMenu()
        checkLateSystemLog()
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
                    let rows = ScrollingCapture.rowSignatures(frame)
                    if let previous = signatures.last, let shift = ScrollStitcher.offset(previous: previous, next: rows) {
                        shifts.append(shift)
                    }
                    frames.append(frame)
                    signatures.append(rows)
                }
                top += 370
            }
            let stitched = ScrollingCapture.stitch(frames: frames, shifts: shifts, signatures: signatures)
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
    private static func writeSyntheticVideo(to url: URL, seconds: Double, size: CGSize, variableRate: Bool = false) async throws {
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

        // Clean asks on its own line, with full button names, in the narrow menu panel.
        if let category = CleanupCategory.all.first(where: { item in item.action == .deleteContents }) {
            let space = SpaceModel.shared
            space.confirmingID = category.id
            render(CleanupRow(model: space, category: category, compact: true).padding(.horizontal, 16).auroraBackground().environment(app).preferredColorScheme(.dark), size: CGSize(width: 360, height: 150), to: folder.appendingPathComponent("space-confirm.png"))
            space.confirmingID = nil
        }

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

        for tab in MenuTab.allCases {
            UserDefaults.standard.set(tab.rawValue, forKey: "menuTab")
            render(MenuBarView().environment(app), size: CGSize(width: 360, height: 719), to: folder.appendingPathComponent("menu-\(tab.rawValue.lowercased()).png"))
            let natural = NSHostingView(rootView: MenuBarView().environment(app)).fittingSize
            print("menu \(tab.rawValue) natural height: \(Int(natural.height))")
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
