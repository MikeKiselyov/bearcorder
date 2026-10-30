// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AVFoundation
import AVKit
import AppKit
import AppCore
import SwiftUI

@MainActor
extension DevChecks {
    /// Two names of one file (how original.* points at a display's file) are recognized as one file,
    /// so picking the display already shown swaps nothing.
    static func checkSameFile(folder: URL) {
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
    static func checkLocalization(folder: URL) {
        check(L("feedback.kind.problem") == "Report a problem", "the app's English text comes from en.lproj", L("feedback.kind.problem"))
        check(L("feedback.kind.tip", "Example") == "Problems and ideas go to the Example repository on GitHub as issues", "values go into the text", L("feedback.kind.tip", "Example"))
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
    static func checkPlayerView() {
        let view = PassivePlayerView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        PlayerView.configure(view)
        check(!view.allowsVideoFrameAnalysis, "the video editor player has no Live Text over the frame")
        check(view.hitTest(CGPoint(x: 100, y: 50)) == nil && !view.acceptsFirstResponder, "clicks and drags on the video go to the marks, not to the player")
        check(view.controlsStyle == .none, "the video editor player has no controls of its own")
    }

    static func checkWhatsNewPictures() {
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
    static func checkPopUpChoices() async {
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
    static func checkTextInput() async {
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
    static func checkFieldSettingsOnOldCaptures() {
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

    static func checkCopyReportButtonFits() {
        let button = CopyReportButton(help: "", stepCount: 999) { _ in }
        let hosting = NSHostingView(rootView: button.environment(AppState.shared))
        let width = hosting.fittingSize.width
        check(width > 0 && width <= 270 - 32, "copy bug report button fits the video side panel", "\(Int(width)) pt")
    }

    static func checkCrashClipMigration() {
        let domain = "\(AppInfo.name).selftest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: domain) else {
            check(false, "crash clip migration: scratch defaults")
            return
        }
        defer { forgetScratchDefaults(defaults, domain: domain) }
        defaults.register(defaults: ["keepCrashClipsDays": 7])
        let days = { defaults.integer(forKey: "keepCrashClipsDays") }

        // Used the app up to 0.8.1, then updated.
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

    /// The result token is cut off the end of a command and nowhere else.
    static func checkAutomationToken() {
        let plain = Automation.splitToken("status")
        check(plain.command == "status" && plain.token == nil, "a command without a token stays as it is", plain.command)
        let tagged = Automation.splitToken("status #id=123-456-789")
        check(tagged.command == "status" && tagged.token == "123-456-789", "the token is cut off the end", "\(tagged.command) / \(tagged.token ?? "nil")")
        let hashInside = Automation.splitToken("choose:editor:Color => #FF8800 #id=42-1-2")
        check(hashInside.command == "choose:editor:Color => #FF8800" && hashInside.token == "42-1-2", "a # inside the command stays", hashInside.command)
        let notAtEnd = Automation.splitToken("type:a #id=1 more")
        check(notAtEnd.command == "type:a #id=1 more" && notAtEnd.token == nil, "a token in the middle is text", notAtEnd.command)
    }

    /// Typing never reaches a clip: letters, ⇧ letters and ⌥ characters are masked, shortcuts and
    /// special keys are shown.
    static func checkKeyLabels() {
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
    static func checkFirstVersionFiles() {
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
    static func checkReportFollowsEdits() {
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
    static func checkSavedNamesAndShortcuts() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-names-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = AppPaths.uniqueURL(in: folder, name: "Sample shot", ext: "png")
        FileManager.default.createFile(atPath: first.path, contents: Data([1]))
        let second = AppPaths.uniqueURL(in: folder, name: "Sample shot", ext: "png")
        FileManager.default.createFile(atPath: second.path, contents: Data([2]))
        let third = AppPaths.uniqueURL(in: folder, name: "Sample shot", ext: "png")
        check(first.lastPathComponent == "Sample shot.png" && second.lastPathComponent == "Sample shot 2.png" && third.lastPathComponent == "Sample shot 3.png", "a saved file never overwrites another", "\(first.lastPathComponent) \(second.lastPathComponent) \(third.lastPathComponent)")

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
    static func checkStepCaptions() {
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
    static func checkRecordingClock() {
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

    /// A fake crash report of this app: the header line and the body macOS writes.
    static func fakeCrashReport(bundleId: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
        let header = "{\"app_name\":\"\(AppInfo.name)\",\"timestamp\":\"\(formatter.string(from: date))\",\"bug_type\":\"309\",\"bundleID\":\"\(bundleId)\",\"name\":\"\(AppInfo.name)\"}"
        let body = """
        {"exception":{"type":"EXC_BREAKPOINT","signal":"SIGTRAP"},"termination":{"indicator":"Trace/BPT trap: 5"},
         "asi":{"libswiftCore.dylib":["Fatal error: Index out of range in \(Feedback.homePath)/Code"]},
         "faultingThread":0,"usedImages":[{"name":"libswiftCore.dylib"},{"name":"\(AppInfo.name)"}],
         "threads":[{"triggered":true,"frames":[{"imageIndex":0,"symbol":"_assertionFailure"},{"imageIndex":1,"symbol":"CaptureStore.selectScreen(_:)"}]}]}
        """
        return header + "\n" + body
    }

    /// A problem report hides the home folder and user name in its text and its zip, keeps the
    /// version, packs only recent crash reports of this app, and a new crash is found on the next launch.
    static func checkFeedback(folder: URL) {
        let model = FeedbackModel(kind: .problem)
        model.details = "It broke"
        let report = model.report
        let versionLine = report.environment.first { field in field.name == AppInfo.name }
        check(versionLine?.value.hasPrefix(Updater.shared.version) == true, "a problem report names the app version", "\(String(describing: versionLine))")
        check(Feedback.redact("open \(Feedback.homePath)/Desktop as \(NSUserName())") == "open ~/Desktop as <user>", "a report hides the home folder and the user name")

        let bundleId = "com.example.app-check"
        let crashFolder = folder.appendingPathComponent("feedback-crashes", isDirectory: true)
        try? FileManager.default.removeItem(at: crashFolder)
        try? FileManager.default.createDirectory(at: crashFolder, withIntermediateDirectories: true)
        let recent = crashFolder.appendingPathComponent("\(AppInfo.name)-2026-10-25-120000.ips")
        let old = crashFolder.appendingPathComponent("\(AppInfo.name)-2026-09-01-120000.ips")
        try? Data(fakeCrashReport(bundleId: bundleId).utf8).write(to: recent)
        try? Data("old crash".utf8).write(to: old)
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-20 * 24 * 3600)], ofItemAtPath: old.path)
        try? Data("other app".utf8).write(to: crashFolder.appendingPathComponent("Safari-2026-10-25-120000.ips"))

        let zipFolder = folder.appendingPathComponent("feedback-zip", isDirectory: true)
        try? FileManager.default.removeItem(at: zipFolder)
        let environment = "\(AppInfo.name): test\nHome: \(Feedback.homePath)"
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
        let inner = unpacked.appendingPathComponent("\(AppInfo.name) logs", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: inner.path)) ?? []
        check(names.contains("environment.txt") && names.contains(recent.lastPathComponent) && !names.contains(old.lastPathComponent) && !names.contains("Safari-2026-10-25-120000.ips"), "the log zip has the environment and only recent crash reports of this app", "\(names)")
        var leaks: [String] = []
        for name in names {
            let text = (try? String(contentsOf: inner.appendingPathComponent(name), encoding: .utf8)) ?? ""
            if text.contains(Feedback.homePath) || text.range(of: "(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: NSUserName()) + "(?![A-Za-z0-9])", options: [.regularExpression, .caseInsensitive]) != nil {
                leaks.append(name)
            }
        }
        check(leaks.isEmpty, "files in the log zip hide the home folder and the user name", "\(leaks)")

        // The crash found on the next launch, and what goes into the issue about it.
        let defaults = UserDefaults(suiteName: "\(AppInfo.name)-feedback-check") ?? .standard
        defaults.removeObject(forKey: Feedback.lastCrashCheckKey)
        check(Feedback.crashSinceLastCheck(in: crashFolder, defaults: defaults, bundleId: bundleId) == nil, "the first launch does not bring up old crashes")
        check(defaults.object(forKey: Feedback.lastCrashCheckKey) is Date, "the first launch remembers when it looked")
        defaults.set(Date().addingTimeInterval(-60), forKey: Feedback.lastCrashCheckKey)
        let found = Feedback.crashSinceLastCheck(in: crashFolder, defaults: defaults, bundleId: bundleId)
        check(found?.lastPathComponent == recent.lastPathComponent, "a crash of this app since the last launch is found", "\(String(describing: found))")
        check(Feedback.crashSinceLastCheck(in: crashFolder, defaults: defaults, bundleId: bundleId) == nil, "the same crash is offered only once")

        // What must not count: another build of the app, a hang, a kill from outside, an older crash, junk.
        let others = folder.appendingPathComponent("feedback-not-crashes", isDirectory: true)
        try? FileManager.default.removeItem(at: others)
        try? FileManager.default.createDirectory(at: others, withIntermediateDirectories: true)
        try? Data(fakeCrashReport(bundleId: "io.github.other.app").utf8).write(to: others.appendingPathComponent("\(AppInfo.name)-other-build.ips"))
        let hang = fakeCrashReport(bundleId: bundleId).replacingOccurrences(of: "\"bug_type\":\"309\"", with: "\"bug_type\":\"288\"")
        try? Data(hang.utf8).write(to: others.appendingPathComponent("\(AppInfo.name)-hang.ips"))
        let killed = fakeCrashReport(bundleId: bundleId).replacingOccurrences(of: "\"termination\":{\"indicator\":\"Trace/BPT trap: 5\"}", with: "\"termination\":{\"namespace\":\"CODESIGNING\",\"indicator\":\"Invalid Page\"}")
        try? Data(killed.utf8).write(to: others.appendingPathComponent("\(AppInfo.name)-codesigning.ips"))
        try? Data("not a report".utf8).write(to: others.appendingPathComponent("\(AppInfo.name)-junk.ips"))
        let older = others.appendingPathComponent("\(AppInfo.name)-older.ips")
        try? Data(fakeCrashReport(bundleId: bundleId).utf8).write(to: older)
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: older.path)
        defaults.set(Date().addingTimeInterval(-60), forKey: Feedback.lastCrashCheckKey)
        let wrong = Feedback.crashSinceLastCheck(in: others, defaults: defaults, bundleId: bundleId)
        check(wrong == nil, "other builds, hangs, kills from outside, older crashes and junk are not offered", "\(String(describing: wrong))")
        check(Feedback.crashSinceLastCheck(in: crashFolder, defaults: defaults, bundleId: "") == nil, "a build without a bundle id offers nothing")

        let crashText = Feedback.crashText(from: recent)
        check(crashText.contains("EXC_BREAKPOINT (SIGTRAP)") && crashText.contains("Fatal error: Index out of range in ~/Code") && crashText.contains("\(AppInfo.name)  CaptureStore.selectScreen(_:)"), "the crash text has the reason, the message and the crashed thread, without the home folder", crashText)
        let scrubbed = Feedback.scrubIdentifiers("{\"crashReporterKey\" : \"ABC-123\",\"userID\":501,\"name\":\"Sample\"}")
        check(scrubbed == "{\"crashReporterKey\":\"<hidden>\",\"userID\":\"<hidden>\",\"name\":\"Sample\"}", "crash reports in the zip hide the Mac's ids", scrubbed)
        let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)["offerCrashReports"] as? Bool
        check(registered == true, "crash reports are offered by default")
        forgetScratchDefaults(defaults, domain: "\(AppInfo.name)-feedback-check")
    }
}
#endif
