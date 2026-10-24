import AVFoundation
import AppKit
import Observation
import QAHelperCore

/// One saved capture: a folder with the original media, metadata and editor state.
struct Capture: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case screenshot
        case video
    }

    var id: UUID
    var kind: Kind
    var createdAt: Date
    var environment: EnvironmentSnapshot
    var duration: Double
    var events: [InputEvent]

    var folder: URL {
        return AppPaths.captures.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    var mediaURL: URL {
        return folder.appendingPathComponent(kind == .screenshot ? "original.png" : "original.mp4")
    }

    var thumbnailURL: URL {
        return folder.appendingPathComponent("thumbnail.jpg")
    }

    /// The macOS crash report, for clips saved automatically after a crash.
    var crashReportURL: URL {
        return folder.appendingPathComponent("crash-report.ips")
    }

    /// The app's unified log for the clip's time span.
    var systemLogURL: URL {
        return folder.appendingPathComponent("system.log")
    }

    /// Editor state (annotations or video edits) as JSON.
    var projectURL: URL {
        return folder.appendingPathComponent("project.json")
    }

    var title: String {
        if !environment.appName.isEmpty { return environment.appName }
        return kind == .screenshot ? "Screenshot" : "Clip"
    }

    var searchText: String {
        return [environment.appName, environment.url, environment.appBundleId, kind.rawValue].joined(separator: " ").lowercased()
    }
}

@MainActor
@Observable
final class CaptureStore {
    static let shared = CaptureStore()

    private(set) var captures: [Capture] = []
    private var thumbnailCache: [UUID: NSImage] = [:]

    private init() {
        load()
    }

    func load() {
        var loaded: [Capture] = []
        let folders = (try? FileManager.default.contentsOfDirectory(at: AppPaths.captures, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for folder in folders {
            let metadata = folder.appendingPathComponent("capture.json")
            guard let data = try? Data(contentsOf: metadata), let capture = try? decoder.decode(Capture.self, from: data) else { continue }
            loaded.append(capture)
        }
        loaded.sort { first, second in first.createdAt > second.createdAt }
        captures = loaded
    }

    /// Moves a media file into the store and writes metadata plus a thumbnail.
    func add(kind: Capture.Kind, mediaFile: URL, environment: EnvironmentSnapshot, events: [InputEvent] = [], duration: Double = 0) throws -> Capture {
        let capture = Capture(id: UUID(), kind: kind, createdAt: Date(), environment: environment, duration: duration, events: events)
        try FileManager.default.createDirectory(at: capture.folder, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: mediaFile, to: capture.mediaURL)
        try save(capture)
        makeThumbnail(for: capture)
        captures.insert(capture, at: 0)
        return capture
    }

    func save(_ capture: Capture) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(capture)
        try data.write(to: capture.folder.appendingPathComponent("capture.json"))
    }

    // MARK: Storage limits

    /// Bytes used by every capture folder, measured off the main thread.
    func measureSizes() async -> [UUID: Int64] {
        var folders: [(id: UUID, folder: URL)] = []
        for capture in captures {
            folders.append((id: capture.id, folder: capture.folder))
        }
        let task = Task.detached(priority: .utility) { () -> [UUID: Int64] in
            var sizes: [UUID: Int64] = [:]
            for entry in folders {
                sizes[entry.id] = CaptureStore.folderSize(entry.folder)
            }
            return sizes
        }
        return await task.value
    }

    nonisolated static func folderSize(_ folder: URL) -> Int64 {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return 0 }
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: Set(keys))
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Applies Settings → Storage. Captures open in an editor are never deleted.
    /// Returns how many captures were deleted.
    @discardableResult
    func cleanUp(maxAgeDays: Int, maxGB: Int) async -> Int {
        if maxAgeDays <= 0 && maxGB <= 0 { return 0 }
        let sizes = await measureSizes()
        var items: [StoragePolicy.Item] = []
        for capture in captures {
            items.append(StoragePolicy.Item(id: capture.id, createdAt: capture.createdAt, bytes: sizes[capture.id] ?? 0))
        }
        var protected: Set<UUID> = []
        for capture in captures where WindowManager.shared.isOpen(id: "screenshot:\(capture.id)") || WindowManager.shared.isOpen(id: "video:\(capture.id)") {
            protected.insert(capture.id)
        }
        let maxBytes = Int64(maxGB) * 1_000_000_000
        let doomed = StoragePolicy.itemsToDelete(items, now: Date(), maxAgeDays: maxAgeDays, maxBytes: maxBytes, protected: protected)
        for id in doomed {
            if let capture = captures.first(where: { item in item.id == id }) {
                delete(capture)
            }
        }
        if !doomed.isEmpty {
            Log.info("storage clean-up deleted \(doomed.count) captures")
        }
        return doomed.count
    }

    func delete(_ capture: Capture) {
        try? FileManager.default.removeItem(at: capture.folder)
        thumbnailCache[capture.id] = nil
        captures.removeAll { item in item.id == capture.id }
    }

    func thumbnail(for capture: Capture) -> NSImage? {
        if let cached = thumbnailCache[capture.id] { return cached }
        if let image = NSImage(contentsOf: capture.thumbnailURL) {
            thumbnailCache[capture.id] = image
            return image
        }
        return nil
    }

    /// Refreshes the thumbnail from an edited render.
    func updateThumbnail(for capture: Capture, image: CGImage) {
        writeThumbnail(image, to: capture.thumbnailURL)
        thumbnailCache[capture.id] = nil
    }

    private func makeThumbnail(for capture: Capture) {
        if capture.kind == .screenshot {
            if let source = CGImageSourceCreateWithURL(capture.mediaURL as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                writeThumbnail(image, to: capture.thumbnailURL)
            }
            return
        }
        let asset = AVURLAsset(url: capture.mediaURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        let time = CMTime(seconds: max(0, capture.duration - 0.5), preferredTimescale: 600)
        if let image = try? generator.copyCGImage(at: time, actualTime: nil) {
            writeThumbnail(image, to: capture.thumbnailURL)
        }
    }

    private func writeThumbnail(_ image: CGImage, to url: URL) {
        let maxSide = 480.0
        let scale = min(1, maxSide / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return }
        ImageFiles.write(scaled, to: url, type: "public.jpeg")
    }
}

enum ImageFiles {
    @discardableResult
    static func write(_ image: CGImage, to url: URL, type: String) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else { return false }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func pngData(_ image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }
}
