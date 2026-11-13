// Developer tools: only in builds with AUTOMATION (debug builds and the e2e app), never in a release.
#if AUTOMATION
import AppKit
import AppCore
import Observation

@MainActor
extension DevChecks {
    /// Showing a thumbnail for the first time fills the cache; that must not redraw the thumbnails
    /// already on screen. A thumbnail that changed on disk must.
    static func checkThumbnailCache() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-thumbnails-\(UUID().uuidString)", isDirectory: true)
        let savedOverride = AppPaths.supportOverride
        AppPaths.supportOverride = folder
        defer {
            AppPaths.supportOverride = savedOverride
            try? FileManager.default.removeItem(at: folder)
        }
        guard let picture = renderTextImage(["Thumbnail"]) else {
            check(false, "thumbnail cache: a picture")
            return
        }
        let first = Capture(id: UUID(), kind: .screenshot, createdAt: Date(), environment: EnvironmentSnapshot(), duration: 0, events: [])
        let second = Capture(id: UUID(), kind: .screenshot, createdAt: Date(), environment: EnvironmentSnapshot(), duration: 0, events: [])
        for capture in [first, second] {
            try? FileManager.default.createDirectory(at: capture.folder, withIntermediateDirectories: true)
            ImageFiles.write(picture, to: capture.thumbnailURL, type: "public.jpeg")
        }
        let store = CaptureStore.shared
        final class Changes {
            var count = 0
        }
        let changes = Changes()
        // A view that shows the first thumbnail.
        let shown = withObservationTracking {
            store.thumbnail(for: first)
        } onChange: {
            changes.count += 1
        }
        let versionBefore = store.thumbnailVersion
        let missed = store.thumbnail(for: second)
        check(shown != nil && missed != nil && changes.count == 0 && store.thumbnailVersion == versionBefore, "loading a thumbnail into the cache does not redraw the thumbnails on screen", "changes: \(changes.count), version: \(versionBefore) -> \(store.thumbnailVersion)")
        check(store.thumbnail(for: first) === shown, "a thumbnail is loaded once and then comes from the cache")
        store.forgetThumbnail(first.id)
        let reloaded = store.thumbnail(for: first)
        check(changes.count == 1 && store.thumbnailVersion == versionBefore + 1 && reloaded != nil && reloaded !== shown, "a changed thumbnail redraws the views and is read again", "changes: \(changes.count), version: \(versionBefore) -> \(store.thumbnailVersion)")
    }

    /// Thumbnails of clips, stitching displays, writing long screenshots and measuring the export
    /// sizes after an edit run off the main thread, through the calls the app makes. A save renders
    /// the picture once.
    static func checkHeavyWorkOffMainThread() async {
        let domain = "\(AppInfo.name).selftest.heavy.\(UUID().uuidString)"
        guard let scratch = UserDefaults(suiteName: domain) else {
            check(false, "heavy work: scratch defaults")
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-heavy-\(UUID().uuidString)", isDirectory: true)
        let savedOverride = AppPaths.supportOverride
        let savedOutput = AppSettings.shared.outputFolderPath
        EditorMemory.override = scratch
        AppPaths.supportOverride = folder
        defer {
            ProjectFileWriter.flushAll()
            AppSettings.shared.outputFolderPath = savedOutput
            EditorMemory.override = nil
            AppPaths.supportOverride = savedOverride
            forgetScratchDefaults(scratch, domain: domain)
            try? FileManager.default.removeItem(at: folder)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let picture = renderTextImage(["Heavy"]), let otherPicture = renderTextImage(["Other display"]) else {
            check(false, "heavy work: pictures")
            return
        }
        _ = HeavyWork.takeMainThreadRuns()
        let store = CaptureStore.shared

        // A saved clip: its thumbnail is made in the background and the views are told when it is there.
        let clipFile = folder.appendingPathComponent("clip.mov")
        do {
            try await writeSyntheticVideo(to: clipFile, seconds: 2, size: CGSize(width: 320, height: 200))
            let versionBefore = store.thumbnailVersion
            let clip = try store.add(kind: .video, mediaFile: clipFile, environment: EnvironmentSnapshot(), duration: 2)
            for _ in 0..<100 where store.thumbnailVersion == versionBefore {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            let onMain = HeavyWork.takeMainThreadRuns()
            check(onMain.isEmpty && store.thumbnail(for: clip) != nil && store.thumbnailVersion > versionBefore, "a saved clip gets its thumbnail off the main thread", "on the main thread: \(onMain), version: \(versionBefore) -> \(store.thumbnailVersion)")
            store.delete(clip)
        } catch {
            check(false, "a saved clip gets its thumbnail off the main thread", "\(error)")
        }

        // "All displays": the pictures of the displays become one file.
        let left = folder.appendingPathComponent("left.png")
        let right = folder.appendingPathComponent("right.png")
        ImageFiles.write(picture, to: left, type: "public.png")
        ImageFiles.write(otherPicture, to: right, type: "public.png")
        let stitchedFile = await ScreenshotCapture.stitchToFile([left, right])
        var onMain = HeavyWork.takeMainThreadRuns()
        let stitchedWidth = ImageFiles.load(stitchedFile)?.width ?? 0
        check(onMain.isEmpty && stitchedWidth == picture.width + otherPicture.width, "the displays are stitched into one picture off the main thread", "on the main thread: \(onMain), width: \(stitchedWidth)")
        try? FileManager.default.removeItem(at: stitchedFile)

        // A long scrolling screenshot is written to its file.
        let longFile = folder.appendingPathComponent("long.png")
        let written = await ImageFiles.writeInBackground(picture, to: longFile, type: "public.png")
        onMain = HeavyWork.takeMainThreadRuns()
        check(onMain.isEmpty && written && ImageFiles.load(longFile)?.width == picture.width, "a long screenshot is written off the main thread", "on the main thread: \(onMain)")

        // An edit in the screenshot editor: the export sizes are measured from the same picture a
        // save writes, without rendering it on the main thread.
        let shot = Capture(id: UUID(), kind: .screenshot, createdAt: Date(), environment: EnvironmentSnapshot(), duration: 0, events: [])
        try? FileManager.default.createDirectory(at: shot.folder, withIntermediateDirectories: true)
        ImageFiles.write(picture, to: shot.mediaURL, type: "public.png")
        guard let document = ScreenshotDocument(capture: shot) else {
            check(false, "heavy work: a screenshot document")
            return
        }
        document.exportSizes = [:]
        let rendersBeforeEdit = document.renderCount
        document.add(Annotation(tool: .rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 60, y: 40), color: .blue, lineWidth: 4))
        for _ in 0..<100 where document.exportSizes.isEmpty {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        onMain = HeavyWork.takeMainThreadRuns()
        let rendersAfterEdit = document.renderCount
        var expectedSizes: [ScreenshotDocument.ExportFormat: Int] = [:]
        if let image = document.render() {
            for format in ScreenshotDocument.ExportFormat.allCases {
                expectedSizes[format] = ScreenshotDocument.encode(image, as: format)?.count
            }
        }
        check(onMain.isEmpty && rendersAfterEdit == rendersBeforeEdit && !expectedSizes.isEmpty && document.exportSizes == expectedSizes, "an edit measures the export sizes off the main thread, from the picture a save writes", "on the main thread: \(onMain), renders: \(rendersAfterEdit - rendersBeforeEdit), sizes: \(document.exportSizes) expected \(expectedSizes)")

        // Save: one render for the file and the thumbnail.
        AppSettings.shared.outputFolderPath = folder.appendingPathComponent("saved", isDirectory: true).path
        let rendersBeforeSave = document.renderCount
        let saved = document.saveToFolder()
        let rendersForSave = document.renderCount - rendersBeforeSave
        var savedBytes = -1
        if let url = saved, let data = try? Data(contentsOf: url) {
            savedBytes = data.count
        }
        check(rendersForSave == 1 && savedBytes == expectedSizes[document.exportFormat] && FileManager.default.fileExists(atPath: shot.thumbnailURL.path), "saving a screenshot renders it once", "renders: \(rendersForSave), bytes: \(savedBytes)")
    }
}
#endif
