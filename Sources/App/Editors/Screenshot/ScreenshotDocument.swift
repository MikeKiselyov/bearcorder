import AppKit
import Observation
import AppCore
import UniformTypeIdentifiers

/// Editable state of one screenshot: the image, marks, crop and badge, with undo.
@MainActor
@Observable
final class ScreenshotDocument {
    struct Snapshot {
        var base: CGImage
        var annotations: [Annotation]
        var crop: CGRect?
    }

    /// What gets saved next to the capture so edits survive reopening.
    struct Project: Codable {
        var annotations: [Annotation]
        var crop: CGRect?
        var showBadge: Bool
        var badgeCorner: BadgeCorner
        var hasCombinedBase: Bool
    }

    /// File type and quality for Save, Drag and the file in Copy. The editor shows how big each one
    /// comes out for the current picture.
    enum ExportFormat: String, CaseIterable, Identifiable {
        case png = "PNG"
        case pngHalf = "PNG, half size"
        case jpegHigh = "JPEG, high"
        case jpegMedium = "JPEG, medium"
        case jpegSmall = "JPEG, small"

        var id: String { rawValue }

        var isPNG: Bool {
            return self == .png || self == .pngHalf
        }

        var fileExtension: String {
            if isPNG {
                return "png"
            }
            return "jpg"
        }

        var typeIdentifier: String {
            if isPNG {
                return "public.png"
            }
            return "public.jpeg"
        }

        /// 0.5 halves the width and height: a Retina screenshot at its size in points.
        var scale: CGFloat {
            if self == .pngHalf || self == .jpegSmall {
                return 0.5
            }
            return 1
        }

        var jpegQuality: Double {
            switch self {
            case .jpegHigh: return 0.9
            case .jpegMedium: return 0.7
            default: return 0.6
            }
        }

        /// The name in the file type menu.
        var title: String {
            switch self {
            case .png: return L("screenshot.format.png")
            case .pngHalf: return L("screenshot.format.pngHalf")
            case .jpegHigh: return L("screenshot.format.jpegHigh")
            case .jpegMedium: return L("screenshot.format.jpegMedium")
            case .jpegSmall: return L("screenshot.format.jpegSmall")
            }
        }

        var detail: String {
            switch self {
            case .png: return L("screenshot.format.png.detail")
            case .pngHalf: return L("screenshot.format.pngHalf.detail")
            case .jpegHigh: return L("screenshot.format.jpegHigh.detail")
            case .jpegMedium: return L("screenshot.format.jpegMedium.detail")
            case .jpegSmall: return L("screenshot.format.jpegSmall.detail")
            }
        }
    }

    /// An image handed to a background task; CGImage is immutable.
    private struct FrozenImage: @unchecked Sendable {
        let image: CGImage
    }

    private(set) var capture: Capture
    private(set) var base: CGImage
    var annotations: [Annotation] = []
    var crop: CGRect?
    var selectedId: UUID?
    // The tool, color, sizes, badge and format start as the last screenshot left them
    // (EditorMemory), and each change is remembered for the next one.
    var tool: AnnotationTool = EditorMemory.screenshotTool {
        didSet {
            if tool != .select { selectedId = nil }
            EditorMemory.screenshotTool = tool
        }
    }
    var color: AnnotationColor = EditorMemory.screenshotColor {
        didSet { EditorMemory.screenshotColor = color }
    }
    // Resizing a selected mark with + and - is about that mark, not the size of new ones.
    var stroke: StrokeSize = EditorMemory.screenshotStroke {
        didSet {
            if selectedId == nil { EditorMemory.screenshotStroke = stroke }
        }
    }
    /// Text and step label size in points, before the image scale.
    var textPoints: CGFloat = EditorMemory.screenshotTextPoints {
        didSet {
            if selectedId == nil { EditorMemory.screenshotTextPoints = textPoints }
        }
    }
    /// New text has no label behind it, only outlined letters.
    var clearTextBackground: Bool = EditorMemory.clearTextBackground {
        didSet { EditorMemory.clearTextBackground = clearTextBackground }
    }
    /// New rectangles and ellipses get a see-through fill of their color.
    var shapeFill: Bool = EditorMemory.shapeFill {
        didSet { EditorMemory.shapeFill = shapeFill }
    }
    var showBadge = EditorMemory.screenshotShowsBadge {
        didSet {
            if !isLoadingProject { EditorMemory.screenshotShowsBadge = showBadge }
        }
    }
    var badgeCorner: BadgeCorner = EditorMemory.screenshotBadgeCorner {
        didSet {
            if !isLoadingProject { EditorMemory.screenshotBadgeCorner = badgeCorner }
        }
    }
    /// An older capture's badge is its own, not a new choice to remember.
    @ObservationIgnored private var isLoadingProject = false
    var exportFormat: ExportFormat = ExportFormat(rawValue: EditorMemory.screenshotFormat) ?? .png {
        didSet { EditorMemory.screenshotFormat = exportFormat.rawValue }
    }
    /// File size in bytes of each export format for the picture as it is now.
    var exportSizes: [ExportFormat: Int] = [:]
    @ObservationIgnored private var sizeTask: Task<Void, Never>?
    var zoom: CGFloat = 1
    var fitRequest = 0
    var message: String?
    /// Id of the text annotation being typed into.
    var editingTextId: UUID?

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    /// Writes the project file off the main thread, shortly after the last change.
    @ObservationIgnored private let projectWriter: ProjectFileWriter

    /// `forEditing` false is for drawing the screenshot elsewhere (a step guide, a comparison):
    /// it shows what was saved with it, never the editor's remembered badge.
    init?(capture: Capture, forEditing: Bool = true) {
        self.capture = capture
        self.projectWriter = EditorProjectFile.writer(for: capture.projectURL)
        if !forEditing {
            showBadge = false
            badgeCorner = .topRight
        }
        let combined = capture.folder.appendingPathComponent("base.png")
        var image: CGImage? = nil
        if FileManager.default.fileExists(atPath: combined.path) {
            image = ImageFiles.load(combined)
        }
        if image == nil {
            image = ImageFiles.load(capture.mediaURL)
        }
        guard let loaded = image else { return nil }
        base = loaded
        loadProject()
        refreshExportSizes()
    }

    // MARK: Sizing

    var imageSize: CGSize {
        return CGSize(width: base.width, height: base.height)
    }

    /// Screenshots are usually 2x; scale marks so they look the same on any image.
    var unit: CGFloat {
        return max(1, CGFloat(base.width) / 1400)
    }

    var lineWidth: CGFloat {
        return stroke.width * unit * 1.2
    }

    var fontSize: CGFloat {
        return textPoints * unit
    }

    var nextStepNumber: Int {
        var highest = 0
        for annotation in annotations where annotation.tool == .step {
            highest = max(highest, annotation.number)
        }
        return highest + 1
    }

    var selected: Annotation? {
        guard let id = selectedId else { return nil }
        return annotations.first { annotation in annotation.id == id }
    }

    // MARK: Editing with undo

    func checkpoint() {
        undoStack.append(Snapshot(base: base, annotations: annotations, crop: crop))
        if undoStack.count > 100 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Snapshot(base: base, annotations: annotations, crop: crop))
        apply(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(base: base, annotations: annotations, crop: crop))
        apply(next)
    }

    private func apply(_ snapshot: Snapshot) {
        base = snapshot.base
        annotations = snapshot.annotations
        crop = snapshot.crop
        selectedId = nil
        editingTextId = nil
        saveProject()
    }

    func add(_ annotation: Annotation) {
        checkpoint()
        annotations.append(annotation)
        saveProject()
    }

    /// Replaces an annotation without a checkpoint (callers checkpoint once per gesture).
    func replace(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { item in item.id == annotation.id }) else { return }
        annotations[index] = annotation
    }

    func deleteSelected() {
        guard let id = selectedId else { return }
        checkpoint()
        annotations.removeAll { annotation in annotation.id == id }
        selectedId = nil
        saveProject()
    }

    func delete(_ id: UUID) {
        checkpoint()
        annotations.removeAll { annotation in annotation.id == id }
        if selectedId == id { selectedId = nil }
        saveProject()
    }

    func setText(_ text: String, for id: UUID) {
        guard let index = annotations.firstIndex(where: { item in item.id == id }) else { return }
        if annotations[index].text == text { return }
        annotations[index].text = text
        saveProject()
    }

    /// An arrow with text left without text becomes a plain arrow.
    func makePlainArrow(_ id: UUID) {
        guard let index = annotations.firstIndex(where: { item in item.id == id }) else { return }
        annotations[index].tool = .arrow
        annotations[index].text = ""
        saveProject()
    }

    /// Color/stroke buttons also restyle the selected mark.
    func applyStyleToSelection() {
        guard let id = selectedId, let index = annotations.firstIndex(where: { item in item.id == id }) else { return }
        checkpoint()
        annotations[index].color = color
        annotations[index].lineWidth = lineWidth
        if annotations[index].tool.hasLabel || annotations[index].tool == .step {
            annotations[index].fontSize = annotations[index].tool == .step ? fontSize * 1.1 : fontSize
        }
        if annotations[index].tool.hasLabel {
            annotations[index].clearBackground = clearTextBackground
        }
        if annotations[index].tool == .rectangle || annotations[index].tool == .ellipse {
            annotations[index].fill = shapeFill
        }
        saveProject()
    }

    /// What the fill buttons change: the label behind text, or the inside of a rectangle or
    /// ellipse. Nil for marks without either.
    enum FillTarget {
        case text
        case shape
    }

    var fillTarget: FillTarget? {
        var targetTool = tool
        if let selectedMark = selected {
            targetTool = selectedMark.tool
        }
        if targetTool.hasLabel {
            return .text
        }
        if targetTool == .rectangle || targetTool == .ellipse {
            return .shape
        }
        return nil
    }

    /// True when the current target has a background or fill.
    var isFilled: Bool {
        if fillTarget == .text {
            return !clearTextBackground
        }
        return shapeFill
    }

    /// The fill buttons: a label or fill on (true) or a transparent background (false),
    /// for new marks of that kind and the selected one.
    func setFilled(_ filled: Bool) {
        if fillTarget == .text {
            clearTextBackground = !filled
        } else {
            shapeFill = filled
        }
        guard let id = selectedId, let index = annotations.firstIndex(where: { item in item.id == id }) else { return }
        checkpoint()
        if annotations[index].tool.hasLabel {
            annotations[index].clearBackground = !filled
        }
        if annotations[index].tool == .rectangle || annotations[index].tool == .ellipse {
            annotations[index].fill = filled
        }
        saveProject()
    }

    /// Places a picture on the screenshot: saved next to it, scaled to fit, centered on `point` (the
    /// middle of the visible area when nil), and selected so it can be moved and resized.
    @discardableResult
    func insertImage(_ image: CGImage, at point: CGPoint? = nil) -> Annotation? {
        let file = capture.folder.appendingPathComponent("placed-\(UUID().uuidString).png")
        guard let data = ImageFiles.pngData(image), (try? data.write(to: file)) != nil else {
            message = L("screenshot.message.imageFailed")
            return nil
        }
        let area = crop ?? CGRect(origin: .zero, size: imageSize)
        var width = CGFloat(image.width)
        var height = CGFloat(image.height)
        let scale = min(1, area.width * 0.45 / width, area.height * 0.6 / height)
        width = width * scale
        height = height * scale
        let center = point ?? CGPoint(x: area.midX, y: area.midY)
        let origin = CGPoint(x: center.x - width / 2, y: center.y - height / 2)
        var annotation = Annotation(tool: .image, start: origin, end: CGPoint(x: origin.x + width, y: origin.y + height), color: color, lineWidth: lineWidth)
        annotation.imagePath = file.path
        add(annotation)
        tool = .select
        selectedId = annotation.id
        message = L("screenshot.message.imageAdded")
        return annotation
    }

    /// What the size buttons change now: text size for text and steps, line width for the rest.
    var sizeIsText: Bool {
        var targetTool = tool
        if let selectedMark = selected {
            targetTool = selectedMark.tool
        }
        return targetTool.hasLabel || targetTool == .step
    }

    /// The size the size buttons show: of the selected mark, or for new marks.
    var sizeValue: Int {
        if sizeIsText {
            if let selectedMark = selected, selectedMark.tool.hasLabel || selectedMark.tool == .step {
                var points = selectedMark.fontSize / unit
                if selectedMark.tool == .step {
                    points = points / 1.1
                }
                return Int(points.rounded())
            }
            return Int(textPoints)
        }
        if let selectedMark = selected {
            return Int(StrokeSize.nearest(toWidth: selectedMark.lineWidth / (unit * 1.2)).width)
        }
        return Int(stroke.width)
    }

    /// + and -: text size for text and steps, line thickness for everything else.
    /// With a mark selected, it grows or shrinks that mark.
    func changeSize(by direction: Int) {
        var targetTool = tool
        if let selectedMark = selected {
            targetTool = selectedMark.tool
        }
        if targetTool.hasLabel || targetTool == .step {
            var current = textPoints
            if let selectedMark = selected {
                current = selectedMark.fontSize / unit
                if selectedMark.tool == .step {
                    current = current / 1.1
                }
            }
            textPoints = TextSizes.stepped(from: current, direction)
        } else {
            var current = stroke
            if let selectedMark = selected {
                current = StrokeSize.nearest(toWidth: selectedMark.lineWidth / (unit * 1.2))
            }
            stroke = current.stepped(direction)
        }
        applySizeToSelection()
    }

    /// Like applyStyleToSelection, but keeps the mark's color.
    func applySizeToSelection() {
        guard let id = selectedId, let index = annotations.firstIndex(where: { item in item.id == id }) else { return }
        checkpoint()
        let mark = annotations[index]
        if mark.tool.hasLabel {
            annotations[index].fontSize = fontSize
        } else if mark.tool == .step {
            annotations[index].fontSize = fontSize * 1.1
        } else {
            annotations[index].lineWidth = lineWidth
        }
        saveProject()
    }

    func setCrop(_ rect: CGRect?) {
        checkpoint()
        if let value = rect {
            let bounds = CGRect(origin: .zero, size: imageSize)
            let clipped = value.intersection(bounds).integral
            crop = clipped.width > 8 && clipped.height > 8 ? clipped : nil
        } else {
            crop = nil
        }
        saveProject()
    }

    /// Puts another image to the right of the current one (scaled to the same height).
    func combine(with other: CGImage) {
        let tallest = max(base.height, other.height)
        let scale = CGFloat(tallest) / CGFloat(base.height)
        guard let stitched = ScreenshotCapture.stitchHorizontally([base, other], gap: Int(24 * unit)) else { return }
        checkpoint()
        if scale != 1 {
            var scaled: [Annotation] = []
            for var annotation in annotations {
                annotation.start = CGPoint(x: annotation.start.x * scale, y: annotation.start.y * scale)
                annotation.end = CGPoint(x: annotation.end.x * scale, y: annotation.end.y * scale)
                var points: [CGPoint] = []
                for point in annotation.points {
                    points.append(CGPoint(x: point.x * scale, y: point.y * scale))
                }
                annotation.points = points
                annotation.lineWidth *= scale
                annotation.fontSize *= scale
                scaled.append(annotation)
            }
            annotations = scaled
        }
        base = stitched
        crop = nil
        ImageFiles.write(stitched, to: capture.folder.appendingPathComponent("base.png"), type: "public.png")
        fitRequest += 1
        saveProject()
    }

    // MARK: Output

    var badgeLines: [String] {
        return capture.environment.badgeLines()
    }

    func render() -> CGImage? {
        return AnnotationRenderer.renderImage(
            base: base,
            annotations: annotations,
            crop: crop,
            badgeLines: showBadge ? badgeLines : nil,
            badgeCorner: badgeCorner,
            badgeScale: unit
        )
    }

    func encoded() -> Data? {
        guard let image = render() else { return nil }
        return ScreenshotDocument.encode(image, as: exportFormat)
    }

    nonisolated static func encode(_ image: CGImage, as format: ExportFormat) -> Data? {
        var output = image
        if format.scale != 1 {
            let width = max(1, Int(CGFloat(image.width) * format.scale))
            let height = max(1, Int(CGFloat(image.height) * format.scale))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let scaled = context.makeImage() else { return nil }
            output = scaled
        }
        let rep = NSBitmapImageRep(cgImage: output)
        if format.isPNG {
            return rep.representation(using: .png, properties: [:])
        }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: format.jpegQuality])
    }

    /// Encodes the picture in every format in the background, shortly after the last change.
    func refreshExportSizes() {
        sizeTask?.cancel()
        sizeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled {
                return
            }
            guard let image = render() else { return }
            let frozen = FrozenImage(image: image)
            let sizes = await Task.detached(priority: .utility) { () -> [ExportFormat: Int] in
                var result: [ExportFormat: Int] = [:]
                for format in ExportFormat.allCases {
                    if let data = ScreenshotDocument.encode(frozen.image, as: format) {
                        result[format] = data.count
                    }
                }
                return result
            }.value
            if !Task.isCancelled {
                exportSizes = sizes
            }
        }
    }

    /// "1.2 MB" for a format, or nil while it is being measured.
    func exportSizeText(_ format: ExportFormat) -> String? {
        guard let bytes = exportSizes[format] else { return nil }
        return DataSizeConverter.describe(Double(bytes)).decimal
    }

    /// Writes the rendered image to a temp file named for sharing (drag and drop, Copy).
    func renderToTemporaryFile() -> URL? {
        guard let data = encoded() else { return nil }
        let folder = AppPaths.temporary.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(AppPaths.exportName(date: capture.createdAt)).appendingPathExtension(exportFormat.fileExtension)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    func copyToPasteboard() {
        guard let image = render(), let png = ImageFiles.pngData(image) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // Image data for chat apps plus a file for Finder and Jira attachments.
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let file = renderToTemporaryFile() {
            item.setString(file.absoluteString, forType: .fileURL)
        }
        pasteboard.writeObjects([item])
        updateThumbnail(image)
        message = L("screenshot.message.copied")
    }

    func saveToFolder() -> URL? {
        guard let data = encoded() else { return nil }
        let url = AppPaths.uniqueURL(in: AppSettings.shared.outputFolder, name: AppPaths.exportName(date: capture.createdAt), ext: exportFormat.fileExtension)
        do {
            try data.write(to: url)
            if let image = render() {
                updateThumbnail(image)
            }
            message = L("screenshot.message.saved", url.deletingLastPathComponent().lastPathComponent)
            return url
        } catch {
            message = L("screenshot.message.saveFailed", error.localizedDescription)
            return nil
        }
    }

    func copyBugReport(format: BugReport.Format) {
        BugReportBuilder.copy(for: capture, timeMap: nil, format: format)
        message = L("editors.message.reportCopied")
    }

    func copyEnvironment() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(capture.environment.markdown(), forType: .string)
        message = L("editors.message.environmentCopied")
    }

    private func updateThumbnail(_ image: CGImage) {
        CaptureStore.shared.updateThumbnail(for: capture, image: image)
    }

    // MARK: Persistence

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

    func saveProject() {
        let project = Project(
            annotations: annotations,
            crop: crop,
            showBadge: showBadge,
            badgeCorner: badgeCorner,
            hasCombinedBase: FileManager.default.fileExists(atPath: capture.folder.appendingPathComponent("base.png").path)
        )
        if let data = try? JSONEncoder().encode(project) {
            projectWriter.schedule(data)
        }
        refreshExportSizes()
    }

    /// Writes the last change now: before the editor closes or the screenshot switches to another screen.
    func flushProject() {
        projectWriter.flush()
    }

    /// Shows another display, or all of them side by side. Switching parks this picture's project
    /// file under its display's name, so the last change is written first: a write still waiting
    /// would land on the other picture's file.
    func switchScreen(to id: String) async throws -> Capture {
        saveProject()
        flushProject()
        return try await CaptureStore.shared.selectScreen(id, of: capture, framesPerSecond: AppState.shared.settings.framesPerSecond)
    }

    private func loadProject() {
        guard let data = try? Data(contentsOf: capture.projectURL), let project = try? JSONDecoder().decode(Project.self, from: data) else { return }
        isLoadingProject = true
        defer { isLoadingProject = false }
        annotations = project.annotations
        crop = project.crop
        showBadge = project.showBadge
        badgeCorner = project.badgeCorner
    }
}
