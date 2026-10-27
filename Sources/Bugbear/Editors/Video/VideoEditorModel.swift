import AVFoundation
import AppKit
import Observation
import BugbearCore

enum VideoTool: String, CaseIterable, Identifiable {
    case select
    case text
    case arrow
    case rectangle
    case blur

    var id: String { rawValue }

    var overlayKind: VideoOverlay.Kind? {
        switch self {
        case .text: return .text
        case .arrow: return .arrow
        case .rectangle: return .rectangle
        case .blur: return .blur
        case .select: return nil
        }
    }
}

/// Selection on the timeline: an overlay or one of the edits.
enum TimelineItem: Equatable {
    case overlay(UUID)
    case cut(Int)
    case speed(Int)
    case freeze(Int)
}

@MainActor
@Observable
final class VideoEditorModel {
    private(set) var capture: Capture
    let asset: AVURLAsset
    let player = AVPlayer()

    var project: VideoProject
    var tool: VideoTool = .select
    var selection: TimelineItem?
    /// The text mark being typed right on the video.
    var editingTextID: UUID?
    /// Range picked on the ruler, in source seconds.
    var range: TimeSpan?
    /// Playhead in source seconds.
    var playhead: Double = 0
    var isPlaying = false
    var thumbnails: [NSImage] = []
    var exportProgress: Double?
    var message: String?
    var isBuilding = false

    @ObservationIgnored private(set) var output: VideoCompositor.Output?
    /// Changes with every rebuilt preview, so size estimates in the sidebar refresh.
    private(set) var outputVersion = 0
    /// How many bits per pixel per second the source clip needed; makes size estimates realistic.
    @ObservationIgnored private var sourceBitsPerPixelSecond: Double?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var undoStack: [VideoProject] = []
    @ObservationIgnored private var redoStack: [VideoProject] = []

    var duration: Double { project.timeline.sourceDuration }

    /// Where the video frame is in the editor window (window points, top-left), for tests that
    /// draw on it with the real mouse.
    @ObservationIgnored var stageVideoRect: CGRect = .zero

    /// The editor opened last, for tests that press its buttons.
    static weak var newest: VideoEditorModel?

    init(capture: Capture) {
        self.capture = capture
        self.asset = AVURLAsset(url: capture.mediaURL)
        var loaded = EditorMemory.newVideoProject(duration: max(capture.duration, 0.1))
        if let data = try? Data(contentsOf: capture.projectURL), let saved = try? JSONDecoder().decode(VideoProject.self, from: data) {
            loaded = saved.repairingMarks()
        }
        project = loaded
        lastSaved = loaded
        VideoEditorModel.newest = self
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.playerTimeChanged(time.seconds)
            }
        }
        let opened = Date()
        Task {
            await loadDuration()
        await measureSource()
            await rebuild(keepPosition: false)
            jumpToLastMarker()
            Log.info(String(format: "video editor: preview ready in %.2fs", Date().timeIntervalSince(opened)))
            await makeThumbnails()
            Log.info(String(format: "video editor: filmstrip ready in %.2fs", Date().timeIntervalSince(opened)))
        }
    }

    /// Opens a clip saved with ⌥⇧M on the marked moment.
    private func jumpToLastMarker() {
        var lastMarker: Double? = nil
        for event in capture.events where event.kind == .marker {
            lastMarker = event.time
        }
        if let marker = lastMarker {
            seek(toSource: marker)
        }
    }

    func tearDown() {
        player.pause()
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
    }

    /// Reads how densely the source clip is encoded, for the file size estimates.
    private func measureSource() async {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }
        guard let rate = try? await track.load(.estimatedDataRate), let size = try? await track.load(.naturalSize) else { return }
        let pixels = Double(size.width * size.height)
        if rate > 0 && pixels > 0 {
            sourceBitsPerPixelSecond = Double(rate) / pixels
            outputVersion += 1
        }
    }

    private func loadDuration() async {
        if let real = try? await asset.load(.duration).seconds, real > 0, abs(real - project.timeline.sourceDuration) > 0.05 {
            // The stored duration was an estimate; keep the user's trim inside the real clip.
            let old = project.timeline
            var timeline = EditTimeline(sourceDuration: real)
            timeline.trim = TimeSpan(start: min(old.trim.start, real), end: min(old.trim.end, real))
            if !old.hasEdits {
                timeline.trim = TimeSpan(start: 0, end: real)
            }
            timeline.cuts = old.cuts
            timeline.speeds = old.speeds
            timeline.freezes = old.freezes
            project.timeline = timeline
        }
    }

    private func makeThumbnails() async {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        // Close enough for a filmstrip, and much faster than exact frames.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        let count = 12
        var times: [CMTime] = []
        for index in 0..<count {
            times.append(CMTime(seconds: duration * (Double(index) + 0.5) / Double(count), preferredTimescale: 600))
        }
        // One batch: the generator decodes in order instead of seeking twelve times.
        var images: [NSImage] = []
        for await result in generator.images(for: times) {
            if let frame = try? result.image {
                images.append(NSImage(cgImage: frame, size: CGSize(width: frame.width, height: frame.height)))
            }
        }
        thumbnails = images
    }

    // MARK: Undo

    /// Call before every change so it can be undone.
    func checkpoint() {
        undoStack.append(project)
        if undoStack.count > 100 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    var canUndo: Bool { !undoStack.isEmpty }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(project)
        project = previous
        selection = nil
        editingTextID = nil
        projectChanged(remembering: false)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project)
        project = next
        projectChanged(remembering: false)
    }

    /// Persists and rebuilds the preview shortly after the last change. Undo and redo pass
    /// `remembering: false`: going back is not a new choice for the next clip.
    func projectChanged(remembering: Bool = true) {
        save(remembering: remembering)
        rebuildTask?.cancel()
        rebuildTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            if Task.isCancelled { return }
            await rebuild(keepPosition: true)
        }
    }

    /// The project as last saved, to remember only the choices that changed since.
    @ObservationIgnored private var lastSaved: VideoProject

    private func save(remembering: Bool = true) {
        if remembering {
            EditorMemory.rememberVideoChanges(from: lastSaved, to: project)
        }
        lastSaved = project
        if let data = try? JSONEncoder().encode(project) {
            try? data.write(to: capture.projectURL)
        }
    }

    // MARK: Preview

    private func rebuild(keepPosition: Bool) async {
        isBuilding = true
        defer { isBuilding = false }
        let sourcePosition = playhead
        do {
            let built = try await VideoCompositor.build(asset: asset, project: project, events: capture.events, environment: capture.environment)
            output = built
            outputVersion += 1
            let item = AVPlayerItem(asset: built.composition)
            item.videoComposition = built.videoComposition
            let wasPlaying = isPlaying
            player.replaceCurrentItem(with: item)
            if keepPosition {
                let outputTime = built.timeMap.outputTime(forSource: sourcePosition)
                await player.seek(to: CMTime(seconds: outputTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            } else {
                playhead = project.timeline.trim.start
            }
            if wasPlaying {
                player.play()
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func playerTimeChanged(_ outputTime: Double) {
        guard let map = output?.timeMap else { return }
        playhead = map.sourceTime(forOutput: outputTime)
        if isPlaying && player.rate == 0 {
            isPlaying = false
        }
    }

    var outputDuration: Double {
        return project.timeline.outputDuration
    }

    var outputPlayhead: Double {
        guard let map = output?.timeMap else { return playhead }
        return map.outputTime(forSource: playhead)
    }

    func togglePlay() {
        if isPlaying {
            player.pause()
            isPlaying = false
            return
        }
        // Start over when at the end.
        if outputPlayhead >= outputDuration - 0.05 {
            seek(toSource: project.timeline.trim.start)
        }
        player.play()
        isPlaying = true
    }

    func seek(toSource time: Double) {
        let clamped = max(0, min(duration, time))
        playhead = clamped
        guard let map = output?.timeMap else { return }
        let target = map.outputTime(forSource: clamped)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func step(seconds: Double) {
        seek(toSource: playhead + seconds)
    }

    // MARK: Edits

    func setTrimStart(_ value: Double) {
        let end = project.timeline.trim.end
        project.timeline.trim = TimeSpan(start: max(0, min(value, end - 0.2)), end: end)
        projectChanged()
    }

    func setTrimEnd(_ value: Double) {
        let start = project.timeline.trim.start
        project.timeline.trim = TimeSpan(start: start, end: min(duration, max(value, start + 0.2)))
        projectChanged()
    }

    /// The span to act on: the ruler selection, or a few seconds from the playhead.
    func actionSpan(defaultLength: Double = 3) -> TimeSpan {
        if let selected = range, selected.duration > 0.05 {
            return selected
        }
        return TimeSpan.mark(at: playhead, length: defaultLength, inside: project.timeline.trim)
    }

    func cutSelection() {
        guard let selected = range, selected.duration > 0.05 else {
            message = "Drag on the ruler to choose what to cut"
            return
        }
        checkpoint()
        project.timeline.cuts.append(selected)
        range = nil
        projectChanged()
    }

    func slowMotion() {
        checkpoint()
        project.timeline.speeds.append(SpeedEdit(span: actionSpan(), factor: 0.5))
        range = nil
        projectChanged()
    }

    func freezeFrame() {
        checkpoint()
        project.timeline.freezes.append(FreezeEdit(at: playhead, duration: 2))
        projectChanged()
    }

    func addOverlay(kind: VideoOverlay.Kind, start: CGPoint, end: CGPoint) {
        checkpoint()
        var overlay = VideoOverlay(kind: kind, span: actionSpan(), start: start, end: end)
        overlay.scale = lastOverlayScale
        if kind == .text {
            overlay.text = ""
            overlay.end = start
            overlay.clearBackground = lastClearText
        }
        project.overlays.append(overlay)
        selection = .overlay(overlay.id)
        tool = .select
        // Text is typed right where it was placed, not in the side panel.
        if kind == .text {
            editingTextID = overlay.id
        }
        projectChanged()
    }

    /// New marks use the size picked last.
    @ObservationIgnored private var lastOverlayScale: Double = 1
    /// New text keeps the background choice made last.
    @ObservationIgnored private var lastClearText = EditorMemory.clearTextBackground

    /// Switches the selected text between a colored label and outlined letters on a transparent background.
    func setSelectedTextClear(_ clear: Bool) {
        guard var overlay = selectedOverlay, overlay.kind == .text else { return }
        checkpoint()
        overlay.clearBackground = clear
        lastClearText = clear
        EditorMemory.clearTextBackground = clear
        updateOverlay(overlay)
    }

    /// + and -: grows or shrinks the selected text, arrow or box.
    func changeSelectedOverlaySize(by direction: Int) {
        guard var overlay = selectedOverlay, overlay.kind != .blur else { return }
        let next = overlay.steppedScale(direction)
        if next == overlay.effectiveScale { return }
        checkpoint()
        overlay.scale = next
        lastOverlayScale = next
        updateOverlay(overlay)
    }

    func updateOverlay(_ overlay: VideoOverlay) {
        guard let index = project.overlays.firstIndex(where: { item in item.id == overlay.id }) else { return }
        project.overlays[index] = overlay
        projectChanged()
    }

    /// Typing on the video ended (Return or a click elsewhere): text left empty is taken away.
    func finishTextEditing(removingEmpty: Bool = true) {
        guard let id = editingTextID else { return }
        editingTextID = nil
        guard removingEmpty, let overlay = project.overlays.first(where: { item in item.id == id }) else { return }
        if overlay.text.trimmingCharacters(in: .whitespaces).isEmpty {
            project.overlays.removeAll { item in item.id == id }
            if selection == .overlay(id) {
                selection = nil
            }
            projectChanged()
        }
    }

    /// Types into a text mark again (a second click on picked text). The change can be undone at once.
    func beginTextEditing(_ id: UUID) {
        finishTextEditing()
        guard project.overlays.contains(where: { item in item.id == id }) else { return }
        checkpoint()
        selection = .overlay(id)
        editingTextID = id
    }

    /// Types into a text mark from the field on the video.
    func setText(_ text: String, of id: UUID) {
        guard let index = project.overlays.firstIndex(where: { item in item.id == id }) else { return }
        if project.overlays[index].text == text { return }
        project.overlays[index].text = text
        projectChanged()
    }

    var selectedOverlay: VideoOverlay? {
        guard case .overlay(let id) = selection else { return nil }
        return project.overlays.first { overlay in overlay.id == id }
    }

    func deleteSelection() {
        guard let item = selection else { return }
        checkpoint()
        switch item {
        case .overlay(let id):
            project.overlays.removeAll { overlay in overlay.id == id }
        case .cut(let index):
            if index < project.timeline.cuts.count { project.timeline.cuts.remove(at: index) }
        case .speed(let index):
            if index < project.timeline.speeds.count { project.timeline.speeds.remove(at: index) }
        case .freeze(let index):
            if index < project.timeline.freezes.count { project.timeline.freezes.remove(at: index) }
        }
        selection = nil
        projectChanged()
    }

    // MARK: Export

    var estimatedSizeText: String {
        let seconds = outputDuration
        var bytes = 0.0
        if project.format == .gif {
            bytes = seconds * Double(project.gifFramesPerSecond) * 90_000
        } else if let limit = project.sizeLimitMB {
            if SizeBudget.cannotFit(limitMB: limit, duration: seconds, hasAudio: true) {
                return "too long for \(limit) MB"
            }
            return "≤ \(limit) MB"
        } else if let estimate = estimatedBytes(for: project.quality) {
            bytes = estimate
        }
        return "≈ " + DataSizeConverter.describe(bytes).decimal
    }

    /// Expected MP4 size at a quality preset, from the bitrate the export uses. Nil before the
    /// preview is built.
    func estimatedBytes(for quality: VideoQuality) -> Double? {
        _ = outputVersion
        guard let built = output else { return nil }
        let preset = SizeBudget.preset(sourceWidth: built.renderSize.width, sourceHeight: built.renderSize.height, maxHeight: quality.maxHeight)
        let hasAudio = !built.composition.tracks(withMediaType: .audio).isEmpty
        let bitrate = SizeBudget.expectedVideoBitrate(presetBitrate: preset.videoBitrate, sourceBitsPerPixelSecond: sourceBitsPerPixelSecond, width: preset.width, height: preset.height)
        return SizeBudget.estimatedBytes(videoBitrate: bitrate, duration: outputDuration, hasAudio: hasAudio)
    }

    /// "1080p · ≈ 12 MB" for the quality menu.
    func qualityLabel(_ quality: VideoQuality) -> String {
        guard let bytes = estimatedBytes(for: quality) else { return quality.rawValue }
        var label = quality.rawValue
        if let built = output, let height = quality.maxHeight, built.renderSize.height <= height {
            label += " (same as original)"
        }
        return label + " · ≈ " + DataSizeConverter.describe(bytes).decimal
    }

    /// Exports to `url`, or to a temp file when nil. Returns the file.
    func export(to url: URL? = nil) async -> URL? {
        guard let built = output else { return nil }
        let ext = project.format == .gif ? "gif" : "mp4"
        let target = url ?? AppPaths.temporary.appendingPathComponent(UUID().uuidString, isDirectory: true).appendingPathComponent(AppPaths.exportName(date: capture.createdAt)).appendingPathExtension(ext)
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        exportProgress = 0
        defer { exportProgress = nil }
        let progress: (Double) -> Void = { value in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.exportProgress = value
                }
            }
        }
        do {
            if project.format == .gif {
                try await VideoCompositor.exportGIF(built, framesPerSecond: project.gifFramesPerSecond, to: target, progress: progress)
            } else {
                try await VideoCompositor.exportMP4(built, quality: project.quality, sizeLimitMB: project.sizeLimitMB, to: target, progress: progress)
                warnIfOverLimit(target)
            }
            return target
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    private func warnIfOverLimit(_ file: URL) {
        guard let limit = project.sizeLimitMB else { return }
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        let bytes = (attributes?[.size] as? NSNumber)?.doubleValue ?? 0
        if bytes > Double(limit) * 1_000_000 {
            message = "The file is \(DataSizeConverter.describe(bytes).decimal), over the \(limit) MB limit. Trim the clip."
        }
    }

    /// Shows the report fields as Settings → Bug reports has them now, and keeps that in the capture.
    /// On opening only which fields show and their names follow; your fields keep the values they
    /// had when the capture was taken, unless you change them while the editor is open.
    func refreshEnvironmentFields(includingYourFields: Bool) {
        var environment = capture.environment
        EnvironmentCollector.applyFieldSettings(to: &environment, includingYourFields: includingYourFields)
        if environment == capture.environment { return }
        capture.environment = environment
        try? CaptureStore.shared.replace(capture)
    }

    /// Steps the bug report has now: steps in cut parts are left out.
    var reportStepCount: Int {
        return BugReportBuilder.stepCount(for: capture, timeMap: output?.timeMap)
    }

    func copyBugReport(format: BugReport.Format) {
        BugReportBuilder.copy(for: capture, timeMap: output?.timeMap, format: format)
        message = "Bug report copied. Paste it into the ticket."
    }

    func saveToFolder() async {
        let ext = project.format == .gif ? "gif" : "mp4"
        let url = AppPaths.uniqueURL(in: AppSettings.shared.outputFolder, name: AppPaths.exportName(date: capture.createdAt), ext: ext)
        if let saved = await export(to: url) {
            message = "Saved \(saved.lastPathComponent)"
            SystemActions.reveal([saved])
        }
    }

    /// Puts the exported file on the clipboard, ready to paste into Jira or Slack.
    func copyFile() async {
        guard let file = await export() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        message = "Copied \(project.format.rawValue) to clipboard"
    }
}
