// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AppKit
import AppCore

@MainActor
extension DevChecks {
    /// Editors write their project file shortly after an edit, off the main thread. Closing an
    /// editor and switching a screenshot to another screen write the last edit right away, to the
    /// picture it belongs to. Runs on scratch defaults and folders.
    static func checkProjectSaves() async {
        let domain = "\(AppInfo.name).selftest.saves.\(UUID().uuidString)"
        guard let scratch = UserDefaults(suiteName: domain) else {
            check(false, "project saves: scratch defaults")
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-saves-\(UUID().uuidString)", isDirectory: true)
        let savedOverride = AppPaths.supportOverride
        EditorMemory.override = scratch
        AppPaths.supportOverride = folder
        defer {
            ProjectFileWriter.flushAll()
            EditorMemory.override = nil
            AppPaths.supportOverride = savedOverride
            forgetScratchDefaults(scratch, domain: domain)
            try? FileManager.default.removeItem(at: folder)
        }
        guard let picture = renderTextImage(["Saves"]), let otherPicture = renderTextImage(["Other screen"]) else {
            check(false, "project saves: pictures")
            return
        }
        let mark = Annotation(tool: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 60, y: 40), color: .blue, lineWidth: 4)

        // Screenshot: an edit, then what closing the editor does. The file must hold the edit at
        // once, not only after the writer's delay.
        let shot = Capture(id: UUID(), kind: .screenshot, createdAt: Date(), environment: EnvironmentSnapshot(), duration: 0, events: [])
        try? FileManager.default.createDirectory(at: shot.folder, withIntermediateDirectories: true)
        ImageFiles.write(picture, to: shot.mediaURL, type: "public.png")
        guard let document = ScreenshotDocument(capture: shot) else {
            check(false, "project saves: a screenshot document")
            return
        }
        document.add(mark)
        document.flushProject()
        let savedMarks = screenshotMarks(at: shot.projectURL)
        check(savedMarks == 1, "closing the screenshot editor writes the last edit to its project file", "marks on disk: \(savedMarks)")

        // Screenshot from two displays: an edit, then a switch to the other display right away.
        // The edit belongs to the first display's picture, parked as edit-display-1.json.
        var twoScreens = Capture(id: UUID(), kind: .screenshot, createdAt: Date(), environment: EnvironmentSnapshot(), duration: 0, events: [])
        twoScreens.screens = [
            ScreenVariant(id: "display-1", name: "First", file: "screen-display-1.png", events: [], isMain: true),
            ScreenVariant(id: "display-2", name: "Second", file: "screen-display-2.png", events: [], isMain: false),
        ]
        twoScreens.selectedScreen = "display-1"
        try? FileManager.default.createDirectory(at: twoScreens.folder, withIntermediateDirectories: true)
        ImageFiles.write(picture, to: twoScreens.folder.appendingPathComponent("screen-display-1.png"), type: "public.png")
        ImageFiles.write(otherPicture, to: twoScreens.folder.appendingPathComponent("screen-display-2.png"), type: "public.png")
        ImageFiles.write(picture, to: twoScreens.mediaURL, type: "public.png")
        guard let switching = ScreenshotDocument(capture: twoScreens) else {
            check(false, "project saves: a two-display screenshot document")
            return
        }
        switching.add(mark)
        do {
            let switched = try await switching.switchScreen(to: "display-2")
            // Longer than the writer's delay: a write that was still waiting has landed by now.
            try? await Task.sleep(nanoseconds: 600_000_000)
            let parkedMarks = screenshotMarks(at: switched.folder.appendingPathComponent("edit-display-1.json"))
            let otherMarks = screenshotMarks(at: switched.projectURL)
            check(parkedMarks == 1 && otherMarks == 0, "switching a screenshot to another display keeps the last edit with the first display's picture", "first: \(parkedMarks), other: \(otherMarks)")
        } catch {
            check(false, "switching a screenshot to another display keeps the last edit with the first display's picture", "\(error)")
        }

        // Video: an edit, then what closing the editor does (the view's onDisappear calls tearDown).
        let clip = Capture(id: UUID(), kind: .video, createdAt: Date(), environment: EnvironmentSnapshot(), duration: 2, events: [])
        try? FileManager.default.createDirectory(at: clip.folder, withIntermediateDirectories: true)
        do {
            try await writeSyntheticVideo(to: clip.mediaURL, seconds: 2, size: CGSize(width: 320, height: 200))
        } catch {
            check(false, "project saves: a clip", "\(error)")
            return
        }
        let model = VideoEditorModel(capture: clip)
        model.project.timeline.cuts = [TimeSpan(start: 0.5, end: 1)]
        model.projectChanged(rebuilding: false)
        model.tearDown()
        var savedCuts = -1
        if let data = try? Data(contentsOf: clip.projectURL), let saved = try? JSONDecoder().decode(VideoProject.self, from: data) {
            savedCuts = saved.timeline.cuts.count
        }
        check(savedCuts == 1, "closing the video editor writes the last edit to its project file", "cuts on disk: \(savedCuts)")
    }

    /// How many marks a screenshot project file holds; 0 when there is no file, -1 when it does not decode.
    private static func screenshotMarks(at url: URL) -> Int {
        guard let data = try? Data(contentsOf: url) else { return 0 }
        guard let project = try? JSONDecoder().decode(ScreenshotDocument.Project.self, from: data) else { return -1 }
        return project.annotations.count
    }
}
#endif
