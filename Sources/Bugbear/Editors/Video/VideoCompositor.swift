import AVFoundation
import AppKit
import CoreImage
import ImageIO
import BugbearCore
import UniformTypeIdentifiers

/// Builds the edited composition for a clip: cuts, speed, freezes, and a Core Image
/// handler that draws overlays, blur, click ripples and keystrokes on every frame.
/// The player and the exporter use the exact same result.
struct VideoCompositor {
    struct Output {
        var composition: AVMutableComposition
        var videoComposition: AVVideoComposition
        var renderSize: CGSize
        var timeMap: TimeMap
        var duration: Double
    }

    /// Pre-rendered pieces the frame handler composites. Immutable, shared with the render thread.
    final class Layers: @unchecked Sendable {
        struct Placed {
            var image: CIImage
            var span: TimeSpan
        }

        var overlays: [Placed] = []
        var blurs: [(rect: CGRect, span: TimeSpan)] = []
        var clicks: [(center: CGPoint, time: Double)] = []
        var keys: [(image: CIImage, time: Double)] = []
        var badge: CIImage?
        var slowBadge: CIImage?
        var ripple: CIImage?
        var pieces: [TimelinePiece] = []
        var renderSize: CGSize = .zero
    }

    static func build(asset: AVAsset, project: VideoProject, events: [InputEvent], environment: EnvironmentSnapshot) async throws -> Output {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw BufferError.exportFailed("Clip has no video")
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let renderSize = CGSize(width: Int(naturalSize.width / 2) * 2, height: Int(naturalSize.height / 2) * 2)

        let pieces = project.timeline.pieces()
        let composition = AVMutableComposition()
        guard let compositionVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw BufferError.exportFailed("Cannot create video track")
        }
        var compositionAudio: AVMutableCompositionTrack? = nil
        if !audioTracks.isEmpty {
            compositionAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }

        // Pieces go back to back from a CMTime cursor. Positions computed in Double and rounded
        // leave tiny gaps after scaling, which makes the video composition invalid (-11841).
        let timescale: CMTimeScale = 60000
        var cursor = CMTime.zero
        for piece in pieces {
            let sourceRange = CMTimeRange(
                start: CMTime(seconds: piece.sourceStart, preferredTimescale: timescale),
                duration: CMTime(seconds: piece.sourceDuration, preferredTimescale: timescale)
            )
            let outputDuration = CMTime(seconds: piece.outputDuration, preferredTimescale: timescale)
            try compositionVideo.insertTimeRange(sourceRange, of: videoTrack, at: cursor)
            let insertedRange = CMTimeRange(start: cursor, duration: sourceRange.duration)
            let isScaled = CMTimeCompare(outputDuration, sourceRange.duration) != 0
            if let audio = compositionAudio, let sourceAudio = audioTracks.first, !piece.isFreeze {
                try? audio.insertTimeRange(sourceRange, of: sourceAudio, at: cursor)
                if isScaled {
                    audio.scaleTimeRange(insertedRange, toDuration: outputDuration)
                }
            }
            if isScaled {
                compositionVideo.scaleTimeRange(insertedRange, toDuration: outputDuration)
            }
            cursor = CMTimeAdd(cursor, outputDuration)
        }

        let layers = makeLayers(project: project, events: events, environment: environment, renderSize: renderSize, pieces: pieces)
        let timeMap = TimeMap(pieces: pieces)

        let videoComposition = AVMutableVideoComposition(asset: composition) { request in
            let outputTime = request.compositionTime.seconds
            let image = VideoCompositor.renderFrame(source: request.sourceImage, outputTime: outputTime, timeMap: timeMap, layers: layers)
            request.finish(with: image, context: nil)
        }
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        // The composition's own duration is exact; summing Doubles can overshoot it by a few
        // microseconds, and an export range past the end fails with -11841.
        return Output(composition: composition, videoComposition: videoComposition, renderSize: renderSize, timeMap: timeMap, duration: composition.duration.seconds)
    }

    // MARK: Pre-rendering

    private static func makeLayers(project: VideoProject, events: [InputEvent], environment: EnvironmentSnapshot, renderSize: CGSize, pieces: [TimelinePiece]) -> Layers {
        let layers = Layers()
        layers.renderSize = renderSize
        layers.pieces = pieces
        let unit = max(1, renderSize.height / 900)

        for overlay in project.overlays {
            let pixelStart = CGPoint(x: overlay.start.x * renderSize.width, y: overlay.start.y * renderSize.height)
            let pixelEnd = CGPoint(x: overlay.end.x * renderSize.width, y: overlay.end.y * renderSize.height)
            if overlay.kind == .blur {
                let rect = CGRect(x: min(pixelStart.x, pixelEnd.x), y: min(pixelStart.y, pixelEnd.y), width: abs(pixelEnd.x - pixelStart.x), height: abs(pixelEnd.y - pixelStart.y))
                // Convert to Core Image coordinates (origin bottom-left).
                let ciRect = CGRect(x: rect.minX, y: renderSize.height - rect.maxY, width: rect.width, height: rect.height)
                layers.blurs.append((rect: ciRect, span: overlay.span))
                continue
            }
            let scale = CGFloat(overlay.effectiveScale)
            var annotation = Annotation(tool: .arrow, start: pixelStart, end: pixelEnd, color: overlay.color, lineWidth: 5 * unit * scale)
            annotation.fontSize = 24 * unit * scale
            switch overlay.kind {
            case .arrow: annotation.tool = .arrow
            case .rectangle: annotation.tool = .rectangle
            case .text:
                annotation.tool = .text
                annotation.text = overlay.text.isEmpty ? "Text" : overlay.text
            case .blur: break
            }
            if let image = renderAnnotation(annotation, canvas: renderSize) {
                layers.overlays.append(Layers.Placed(image: image, span: overlay.span))
            }
        }

        if project.showClicks {
            for event in events where event.kind == .click {
                let center = CGPoint(x: event.x * renderSize.width, y: renderSize.height - event.y * renderSize.height)
                layers.clicks.append((center: center, time: event.time))
            }
            layers.ripple = rippleImage(diameter: 70 * unit)
        }

        if project.showKeys {
            var cache: [String: CIImage] = [:]
            for event in events where event.kind == .key {
                var image = cache[event.label]
                if image == nil {
                    image = keyBadgeImage(event.label, unit: unit)
                    cache[event.label] = image
                }
                guard let badge = image else { continue }
                let x = (renderSize.width - badge.extent.width) / 2
                let placed = badge.transformed(by: CGAffineTransform(translationX: x, y: 40 * unit))
                layers.keys.append((image: placed, time: event.time))
            }
        }

        if project.showBadge {
            layers.badge = renderBadge(lines: environment.badgeLines(), corner: project.badgeCorner, canvas: renderSize, unit: unit)
        }
        if let slow = keyBadgeImage("0.5×  slow motion", unit: unit, fill: NSColor(hex: 0xFFC93C), text: NSColor(hex: 0x1A0B06)) {
            layers.slowBadge = slow.transformed(by: CGAffineTransform(translationX: 24 * unit, y: renderSize.height - slow.extent.height - 24 * unit))
        }
        return layers
    }

    /// Draws one annotation into a transparent full-size canvas and crops it to its bounds.
    private static func renderAnnotation(_ annotation: Annotation, canvas: CGSize) -> CIImage? {
        let padding = annotation.lineWidth * 4 + 8
        let bounds = annotation.bounds.insetBy(dx: -padding, dy: -padding).intersection(CGRect(origin: .zero, size: canvas)).integral
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        guard let context = CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        AnnotationRenderer.draw([annotation], baseImage: nil, in: context)
        guard let cgImage = context.makeImage() else { return nil }
        // Place in Core Image space (origin bottom-left).
        return CIImage(cgImage: cgImage).transformed(by: CGAffineTransform(translationX: bounds.minX, y: canvas.height - bounds.maxY))
    }

    private static func renderBadge(lines: [String], corner: BadgeCorner, canvas: CGSize, unit: CGFloat) -> CIImage? {
        guard let context = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: canvas.height)
        context.scaleBy(x: 1, y: -1)
        AnnotationRenderer.drawBadge(lines: lines, corner: corner, bounds: CGRect(origin: .zero, size: canvas), scale: unit * 1.2, in: context)
        guard let image = context.makeImage() else { return nil }
        return CIImage(cgImage: image)
    }

    private static func rippleImage(diameter: CGFloat) -> CIImage? {
        let size = Int(diameter + 8)
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 4, y: 4, width: diameter, height: diameter)
        context.setFillColor(NSColor(hex: 0xFFC93C, alpha: 0.35).cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(NSColor(hex: 0xFFC93C).cgColor)
        context.setLineWidth(max(3, diameter / 18))
        context.strokeEllipse(in: rect.insetBy(dx: 2, dy: 2))
        guard let image = context.makeImage() else { return nil }
        return CIImage(cgImage: image)
    }

    private static func keyBadgeImage(_ label: String, unit: CGFloat, fill: NSColor = NSColor(hex: 0x1C1D20, alpha: 0.92), text: NSColor = NSColor(hex: 0xECEDEE)) -> CIImage? {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22 * unit, weight: .semibold),
            .foregroundColor: text,
        ]
        let textSize = (label as NSString).size(withAttributes: attributes)
        let padding = 14 * unit
        let width = Int(ceil(textSize.width + padding * 2))
        let height = Int(ceil(textSize.height + padding * 1.2))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        fill.setFill()
        NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), xRadius: 10 * unit, yRadius: 10 * unit).fill()
        (label as NSString).draw(at: CGPoint(x: padding, y: padding * 0.6), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { return nil }
        return CIImage(cgImage: image)
    }

    // MARK: Per-frame rendering (render thread)

    static func renderFrame(source: CIImage, outputTime: Double, timeMap: TimeMap, layers: Layers) -> CIImage {
        let sourceTime = timeMap.sourceTime(forOutput: outputTime)
        var image = source

        for blur in layers.blurs where blur.span.contains(sourceTime) {
            let side = min(blur.rect.width, blur.rect.height)
            let pixellate = CIFilter(name: "CIPixellate")
            pixellate?.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
            pixellate?.setValue(max(8, min(40, side / 4)), forKey: kCIInputScaleKey)
            pixellate?.setValue(CIVector(x: blur.rect.midX, y: blur.rect.midY), forKey: kCIInputCenterKey)
            if let pixelated = pixellate?.outputImage?.cropped(to: blur.rect) {
                image = pixelated.composited(over: image)
            }
        }

        for overlay in layers.overlays where overlay.span.contains(sourceTime) {
            image = overlay.image.composited(over: image)
        }

        if let ripple = layers.ripple {
            for click in layers.clicks {
                let age = sourceTime - click.time
                if age < 0 || age > 0.6 { continue }
                let progress = age / 0.6
                let scale = 0.45 + 0.55 * progress
                let alpha = 1 - progress
                let size = ripple.extent.width
                let transform = CGAffineTransform(translationX: -size / 2, y: -size / 2)
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                    .concatenating(CGAffineTransform(translationX: click.center.x, y: click.center.y))
                let faded = ripple.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
                image = faded.transformed(by: transform).composited(over: image)
            }
        }

        // Only the latest keystroke within its display window.
        var latestKey: CIImage? = nil
        for key in layers.keys where sourceTime >= key.time && sourceTime - key.time < 1.4 {
            latestKey = key.image
        }
        if let key = latestKey {
            image = key.composited(over: image)
        }

        if let slow = layers.slowBadge {
            for piece in layers.pieces where !piece.isFreeze && outputTime >= piece.outputStart && outputTime < piece.outputEnd {
                if piece.outputDuration > piece.sourceDuration * 1.05 {
                    image = slow.composited(over: image)
                }
            }
        }

        if let badge = layers.badge {
            image = badge.composited(over: image)
        }
        return image.cropped(to: CGRect(origin: .zero, size: layers.renderSize))
    }

    // MARK: Export

    static func exportMP4(_ output: Output, quality: VideoQuality, sizeLimitMB: Int? = nil, to url: URL, progress: ((Double) -> Void)?) async throws {
        var maxHeight = quality.maxHeight
        var videoBitrate: Int? = nil
        if let limit = sizeLimitMB {
            let hasAudio = !output.composition.tracks(withMediaType: .audio).isEmpty
            let bitrate = SizeBudget.videoBitrate(limitMB: limit, duration: output.duration, hasAudio: hasAudio)
            videoBitrate = bitrate
            if let budgetHeight = SizeBudget.maxHeight(forVideoBitrate: bitrate) {
                let presetHeight = maxHeight ?? Double.infinity
                maxHeight = min(presetHeight, budgetHeight)
            }
        }
        var size = output.renderSize
        if let height = maxHeight, size.height > height {
            let ratio = height / size.height
            size = CGSize(width: Int(size.width * ratio / 2) * 2, height: Int(height / 2) * 2)
        }
        var options = AssetExporter.Options(renderSize: size, framesPerSecond: 30, timeRange: CMTimeRange(start: .zero, duration: output.composition.duration))
        options.videoBitrate = videoBitrate
        try await AssetExporter.export(asset: output.composition, videoComposition: output.videoComposition, options: options, to: url, progress: progress)
    }

    /// Renders an MP4 first, then samples it into an animated GIF.
    static func exportGIF(_ output: Output, framesPerSecond: Int, to url: URL, progress: ((Double) -> Void)?) async throws {
        let temporary = AppPaths.temporary.appendingPathComponent("gif-source-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try await exportMP4(output, quality: .p720, to: temporary) { value in
            progress?(value * 0.6)
        }
        let asset = AVURLAsset(url: temporary)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 960, height: 960)

        let frameCount = max(1, Int(output.duration * Double(framesPerSecond)))
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw BufferError.exportFailed("Cannot create GIF")
        }
        let fileProperties: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        let frameProperties: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(framesPerSecond)]]
        for index in 0..<frameCount {
            let time = CMTime(seconds: Double(index) / Double(framesPerSecond), preferredTimescale: 600)
            if let frame = try? await generator.image(at: time).image {
                CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
            }
            progress?(0.6 + 0.4 * Double(index + 1) / Double(frameCount))
        }
        if !CGImageDestinationFinalize(destination) {
            throw BufferError.exportFailed("Could not write GIF")
        }
    }
}
