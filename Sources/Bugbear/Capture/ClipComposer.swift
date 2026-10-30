import AVFoundation
import AppKit
import BugbearCore
import QuartzCore

/// How displays are arranged in an exported clip, used to place recorded clicks.
struct ClipLayout {
    struct Display {
        var frame: CGRect
        var x: Double
        var width: Double
    }

    var displays: [Display]
    var totalWidth: Double
    /// A recorded area (global AppKit points), on one display or across several.
    var area: CGRect? = nil

    /// Normalized clip position (origin top-left) for a global AppKit point.
    func normalizedPoint(forGlobal point: CGPoint) -> CGPoint? {
        if let area {
            return AreaComposition.normalizedPoint(point, area: area)
        }
        for display in displays where display.frame.contains(point) {
            let localX = (point.x - display.frame.minX) / display.frame.width
            let localY = 1 - (point.y - display.frame.minY) / display.frame.height
            let x = (display.x + localX * display.width) / totalWidth
            return CGPoint(x: x, y: localY)
        }
        return nil
    }
}

/// Result of exporting from the buffers.
struct ClipExport {
    var url: URL
    var pieces: [ClipPiece]
    var duration: Double
    var layout: ClipLayout

    /// Wall-clock span from the first to the last kept moment.
    var wallClockSpan: (start: Date, end: Date)? {
        guard let first = pieces.first, let last = pieces.last else { return nil }
        let now = CACurrentMediaTime()
        let start = Date(timeIntervalSinceNow: first.hostStart - now)
        let end = Date(timeIntervalSinceNow: last.hostEnd - now)
        return (start: start, end: end)
    }

    /// Clip time for a host time, or nil if it fell in a removed pause.
    func outputTime(forHost time: Double) -> Double? {
        for piece in pieces where time >= piece.hostStart && time <= piece.hostEnd {
            return piece.outputStart + (time - piece.hostStart)
        }
        return nil
    }
}

/// Combines one or more display buffers into a single MP4: side by side for several
/// displays, or an area (global points) that may cross displays, each in its place (AreaComposition).
enum ClipComposer {
    /// `audioFrom` is the buffer that holds the sound (the main display's); it may be outside `buffers`
    /// when one other display is saved on its own.
    static func export(buffers: [ScreenBuffer], ranges: [(start: Double, end: Double)], area: CGRect?, framesPerSecond: Int, audioFrom: ScreenBuffer? = nil) async throws -> ClipExport {
        guard let primary = buffers.first else { throw BufferError.noDisplay }
        let audioSource = audioFrom ?? primary
        // Every buffer repeats its last frame at the moment of saving, so a still screen reaches it.
        let saveMoment = CACurrentMediaTime()
        for buffer in buffers {
            await buffer.catchUp(now: saveMoment)
            await buffer.prepareForExport()
        }
        let now = CACurrentMediaTime()
        Log.info("compose: segments \(primary.describeSegments())")
        for range in ranges {
            Log.info(String(format: "compose: requested %.2f…%.2f (relative to now)", range.start - now, range.end - now))
        }
        guard let available = primary.availability() else { throw BufferError.nothingRecorded }

        // Clamp to what the primary display has, and lay the ranges back to back.
        var pieces: [ClipPiece] = []
        var cursor = 0.0
        for range in ranges.sorted(by: { first, second in first.start < second.start }) {
            let start = max(range.start, available.start)
            let end = min(range.end, available.end)
            if end - start < 0.05 { continue }
            pieces.append(ClipPiece(hostStart: start, hostEnd: end, outputStart: cursor))
            cursor += end - start
        }
        Log.info("compose: available \(String(format: "%.2f", available.end - available.start))s, pieces=\(pieces.count), output \(String(format: "%.2f", cursor))s")
        if cursor < 0.2 { throw BufferError.nothingRecorded }

        let composition = AVMutableComposition()
        var placed: [(track: AVMutableCompositionTrack, buffer: ScreenBuffer, sizes: [SegmentSizes.Span], pixels: CGSize)] = []
        for buffer in buffers {
            // Audio is recorded on the main display's buffer only.
            if let added = try await buffer.addTracks(to: composition, pieces: pieces, includeAudio: buffer === audioSource) {
                // A display that went to native resolution while recording has a smaller part first;
                // the biggest picture sets its density in the clip.
                let pixels = SegmentSizes.largest(added.sizes) ?? buffer.size
                placed.append((track: added.track, buffer: buffer, sizes: added.sizes, pixels: pixels))
            }
        }
        guard !placed.isEmpty else { throw BufferError.nothingRecorded }
        if !buffers.contains(where: { buffer in buffer === audioSource }) {
            // Take the sound from the main display's buffer and drop its picture. Its segment ends at
            // its last frame, so it catches up too, or the sound would stop there.
            await audioSource.catchUp(now: saveMoment)
            await audioSource.prepareForExport()
            if let picture = try await audioSource.addTracks(to: composition, pieces: pieces, includeAudio: true) {
                composition.removeTrack(picture.track)
            }
        }

        // Arrange: displays left to right by position, scaled to the primary's height.
        let sorted = placed.sorted { first, second in first.buffer.displayFrame.minX < second.buffer.displayFrame.minX }
        let targetHeight = Double(primary.size.height)
        var layoutDisplays: [ClipLayout.Display] = []
        var layers: [AVMutableVideoCompositionLayerInstruction] = []
        var x = 0.0
        var renderSize = CGSize.zero

        var sources: [AreaComposition.Source] = []
        for item in placed {
            sources.append(AreaComposition.Source(frame: item.buffer.displayFrame, pixels: item.pixels))
        }
        var plan: AreaComposition.Plan?
        if let area {
            plan = AreaComposition.plan(area: area, sources: sources)
            if plan == nil { throw BufferError.nothingRecorded }
        }
        if let plan {
            for placement in plan.placements {
                let item = placed[placement.index]
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: item.track)
                if item.sizes.isEmpty {
                    layer.setTransform(placement.transform, at: .zero)
                }
                // Each part of the picture is scaled by its own size, from where it starts in the clip.
                for (index, span) in item.sizes.enumerated() {
                    let at = index == 0 ? CMTime.zero : CMTime(seconds: span.outputStart, preferredTimescale: 600)
                    layer.setTransform(placement.transform(for: span.pixels, planned: item.pixels), at: at)
                }
                layers.append(layer)
                layoutDisplays.append(ClipLayout.Display(frame: item.buffer.displayFrame, x: Double(placement.offset.x), width: Double(item.pixels.width * placement.scale)))
            }
            renderSize = plan.renderSize
            x = Double(renderSize.width)
        } else {
            for item in sorted {
                let size = item.pixels
                let scale = targetHeight / Double(size.height)
                let width = Double(size.width) * scale
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: item.track)
                let transform = CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: x, y: 0))
                // The first part sets the scale at the start; without a usable one the planned scale does.
                var startCovered = false
                if let first = item.sizes.first, first.pixels.height > 0 {
                    startCovered = true
                }
                if !startCovered {
                    layer.setTransform(transform, at: .zero)
                }
                for (index, span) in item.sizes.enumerated() where span.pixels.height > 0 {
                    let partScale = targetHeight / Double(span.pixels.height)
                    let partTransform = CGAffineTransform(scaleX: partScale, y: partScale).concatenating(CGAffineTransform(translationX: x, y: 0))
                    let at = index == 0 ? CMTime.zero : CMTime(seconds: span.outputStart, preferredTimescale: 600)
                    layer.setTransform(partTransform, at: at)
                }
                layers.append(layer)
                layoutDisplays.append(ClipLayout.Display(frame: item.buffer.displayFrame, x: x, width: width))
                x += width
            }
            renderSize = CGSize(width: Int(x / 2) * 2, height: Int(targetHeight / 2) * 2)
        }

        // Use the exact composition length (summed Doubles can run past the end).
        let exactDuration = composition.duration
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: exactDuration)
        instruction.backgroundColor = NSColor.black.cgColor
        instruction.layerInstructions = layers
        videoComposition.instructions = [instruction]

        let url = AppPaths.temporary.appendingPathComponent("clip-\(UUID().uuidString).mp4")
        // One display, whole screen, at most one sound track: the buffer's H.264 can be copied as is,
        // which takes a fraction of a second however busy the screen was.
        let audioTracks = composition.tracks(withMediaType: .audio).count
        var copied = false
        // A picture that changes size on the way cannot be copied into one track as is.
        if placed.count == 1 && area == nil && audioTracks <= 1 && placed[0].sizes.count <= 1 {
            copied = await copyWithoutReencoding(composition, duration: exactDuration, to: url)
        }
        if !copied {
            let options = AssetExporter.Options(renderSize: renderSize, framesPerSecond: framesPerSecond, timeRange: CMTimeRange(start: .zero, duration: exactDuration))
            try await AssetExporter.export(asset: composition, videoComposition: videoComposition, options: options, to: url)
        }

        let layout = ClipLayout(displays: layoutDisplays, totalWidth: x, area: plan == nil ? nil : area)
        return ClipExport(url: url, pieces: pieces, duration: exactDuration.seconds, layout: layout)
    }

    /// Passthrough export. Returns false (and leaves no file) when the session cannot copy the samples.
    /// Where clicks land when these displays are shown side by side, the way `export` and
    /// `sideBySide(files:)` arrange them: left to right, scaled to the first buffer's height.
    static func sideBySideLayout(_ buffers: [ScreenBuffer]) -> ClipLayout {
        guard let primary = buffers.first else { return ClipLayout(displays: [], totalWidth: 1) }
        let sorted = buffers.sorted { first, second in first.displayFrame.minX < second.displayFrame.minX }
        let targetHeight = Double(primary.size.height)
        var displays: [ClipLayout.Display] = []
        var x = 0.0
        for buffer in sorted {
            let width = Double(buffer.size.width) * targetHeight / Double(buffer.size.height)
            displays.append(ClipLayout.Display(frame: buffer.displayFrame, x: x, width: width))
            x += width
        }
        return ClipLayout(displays: displays, totalWidth: x)
    }

    /// Builds one clip with saved per-display clips side by side, in the given order, scaled to the
    /// height of `files[mainIndex]`, with that clip's sound.
    static func sideBySide(files: [URL], mainIndex: Int, framesPerSecond: Int, to url: URL) async throws {
        let composition = AVMutableComposition()
        // The assets stay referenced until the end: a track whose asset is gone cannot be read (-12780).
        var assets: [AVURLAsset] = []
        var sources: [(track: AVAssetTrack, size: CGSize, range: CMTimeRange)] = []
        for file in files {
            let asset = AVURLAsset(url: file)
            assets.append(asset)
            guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw BufferError.nothingRecorded }
            let size = try await video.load(.naturalSize)
            let trackRange = try await video.load(.timeRange)
            sources.append((track: video, size: size, range: trackRange))
        }
        guard mainIndex < sources.count else { throw BufferError.nothingRecorded }
        // The shortest picture sets the length, so every display has frames to the end.
        var duration = sources[0].range.duration
        for source in sources where source.range.duration < duration {
            duration = source.range.duration
        }
        let range = CMTimeRange(start: .zero, duration: duration)
        let targetHeight = sources[mainIndex].size.height
        var layers: [AVMutableVideoCompositionLayerInstruction] = []
        var x = 0.0
        for source in sources {
            guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try track.insertTimeRange(CMTimeRange(start: source.range.start, duration: duration), of: source.track, at: .zero)
            let scale = targetHeight / source.size.height
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layer.setTransform(CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: x, y: 0)), at: .zero)
            layers.append(layer)
            x += Double(source.size.width * scale)
        }
        for audio in try await assets[mainIndex].loadTracks(withMediaType: .audio) {
            if let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try? track.insertTimeRange(CMTimeRangeGetIntersection(range, otherRange: try await audio.load(.timeRange)), of: audio, at: .zero)
            }
        }
        let renderSize = CGSize(width: Int(x / 2) * 2, height: Int(targetHeight / 2) * 2)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = range
        instruction.backgroundColor = NSColor.black.cgColor
        instruction.layerInstructions = layers
        videoComposition.instructions = [instruction]
        let options = AssetExporter.Options(renderSize: renderSize, framesPerSecond: framesPerSecond, timeRange: range)
        try await AssetExporter.export(asset: composition, videoComposition: videoComposition, options: options, to: url)
        withExtendedLifetime(assets) {}
    }

    private static func copyWithoutReencoding(_ composition: AVMutableComposition, duration: CMTime, to url: URL) async -> Bool {
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { return false }
        try? FileManager.default.removeItem(at: url)
        session.outputURL = url
        session.outputFileType = .mp4
        session.timeRange = CMTimeRange(start: .zero, duration: duration)
        session.shouldOptimizeForNetworkUse = true
        let started = CACurrentMediaTime()
        await session.export()
        if session.status != .completed {
            Log.info("compose: passthrough failed (\(session.error?.localizedDescription ?? "unknown")), re-encoding")
            try? FileManager.default.removeItem(at: url)
            return false
        }
        Log.info(String(format: "compose: copied without re-encoding in %.2fs", CACurrentMediaTime() - started))
        return true
    }
}
