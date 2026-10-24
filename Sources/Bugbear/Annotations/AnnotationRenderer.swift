import AppKit

enum BadgeCorner: String, CaseIterable, Codable, Identifiable {
    case topRight
    case topLeft
    case bottomRight
    case bottomLeft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topRight: return "Top right"
        case .topLeft: return "Top left"
        case .bottomRight: return "Bottom right"
        case .bottomLeft: return "Bottom left"
        }
    }
}

/// Draws annotations with AppKit into a y-down context. Used by the screenshot canvas,
/// the PNG export and the live on-screen overlay, so all three look identical.
enum AnnotationRenderer {
    /// `context` must already be y-down in document units. `baseImage` is in the same units
    /// (needed only for blur and magnifier).
    static func draw(_ annotations: [Annotation], baseImage: CGImage?, in context: CGContext) {
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        for annotation in annotations {
            draw(annotation, baseImage: baseImage)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    static func draw(_ annotation: Annotation, baseImage: CGImage?) {
        let color = annotation.color.nsColor
        switch annotation.tool {
        case .arrow:
            drawArrow(from: annotation.start, to: annotation.end, width: annotation.lineWidth, color: color)
        case .line:
            withShadow(width: annotation.lineWidth) {
                let path = NSBezierPath()
                path.move(to: annotation.start)
                path.line(to: annotation.end)
                path.lineWidth = annotation.lineWidth
                path.lineCapStyle = .round
                color.setStroke()
                path.stroke()
            }
        case .rectangle:
            withShadow(width: annotation.lineWidth) {
                let radius = annotation.lineWidth * 1.5
                let path = NSBezierPath(roundedRect: annotation.rect, xRadius: radius, yRadius: radius)
                path.lineWidth = annotation.lineWidth
                color.setStroke()
                path.stroke()
            }
        case .ellipse:
            withShadow(width: annotation.lineWidth) {
                let path = NSBezierPath(ovalIn: annotation.rect)
                path.lineWidth = annotation.lineWidth
                color.setStroke()
                path.stroke()
            }
        case .pen:
            withShadow(width: annotation.lineWidth) {
                let path = smoothPath(annotation.points)
                path.lineWidth = annotation.lineWidth
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                color.setStroke()
                path.stroke()
            }
        case .highlighter:
            let path = smoothPath(annotation.points)
            path.lineWidth = annotation.lineWidth * 5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            color.withAlphaComponent(0.38).setStroke()
            path.stroke()
        case .text:
            drawTextLabel(annotation)
        case .step:
            drawStep(annotation)
        case .blur:
            drawPixelated(rect: annotation.rect, baseImage: baseImage)
        case .magnifier:
            drawMagnifier(annotation, baseImage: baseImage)
        case .select, .crop:
            break
        }
    }

    private static func withShadow(width: CGFloat, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = max(2, width)
        shadow.shadowOffset = NSSize(width: 0, height: -width * 0.3)
        shadow.set()
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    static func drawArrow(from start: CGPoint, to end: CGPoint, width: CGFloat, color: NSColor) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, hypot(dx, dy))
        let headLength = min(length * 0.6, max(width * 4.5, 14))
        let headWidth = headLength * 0.8
        let unitX = dx / length
        let unitY = dy / length
        let baseX = end.x - unitX * headLength
        let baseY = end.y - unitY * headLength
        let normalX = -unitY
        let normalY = unitX

        withShadow(width: width) {
            let shaft = NSBezierPath()
            shaft.move(to: start)
            shaft.line(to: CGPoint(x: baseX + unitX * 1, y: baseY + unitY * 1))
            shaft.lineWidth = width
            shaft.lineCapStyle = .round
            color.setStroke()
            shaft.stroke()

            let head = NSBezierPath()
            head.move(to: end)
            head.line(to: CGPoint(x: baseX + normalX * headWidth / 2, y: baseY + normalY * headWidth / 2))
            head.line(to: CGPoint(x: baseX - normalX * headWidth / 2, y: baseY - normalY * headWidth / 2))
            head.close()
            head.lineJoinStyle = .round
            head.lineWidth = width * 0.6
            color.setFill()
            color.setStroke()
            head.fill()
            head.stroke()
        }
    }

    static func smoothPath(_ points: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count < 3 {
            for point in points.dropFirst() {
                path.line(to: point)
            }
            return path
        }
        // Quadratic smoothing through midpoints.
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let middle = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.curve(to: middle, controlPoint1: previous, controlPoint2: previous)
        }
        if let last = points.last {
            path.line(to: last)
        }
        return path
    }

    static func textAttributes(_ annotation: Annotation) -> [NSAttributedString.Key: Any] {
        return [
            .font: NSFont.systemFont(ofSize: annotation.fontSize, weight: .bold),
            .foregroundColor: annotation.color.contrastingText,
        ]
    }

    static func textSize(_ annotation: Annotation) -> CGSize {
        let text = annotation.text.isEmpty ? "Text" : annotation.text
        let size = (text as NSString).boundingRect(with: CGSize(width: 10000, height: 10000), options: [.usesLineFragmentOrigin], attributes: textAttributes(annotation)).size
        let padding = annotation.fontSize * 0.45
        return CGSize(width: ceil(size.width) + padding * 2, height: ceil(size.height) + padding * 1.2)
    }

    static func drawTextLabel(_ annotation: Annotation) {
        let text = annotation.text.isEmpty ? "Text" : annotation.text
        let size = textSize(annotation)
        let box = CGRect(origin: annotation.start, size: size)
        withShadow(width: 2) {
            let path = NSBezierPath(roundedRect: box, xRadius: annotation.fontSize * 0.3, yRadius: annotation.fontSize * 0.3)
            annotation.color.nsColor.setFill()
            path.fill()
        }
        let padding = annotation.fontSize * 0.45
        let origin = CGPoint(x: box.minX + padding, y: box.minY + padding * 0.6)
        (text as NSString).draw(with: CGRect(origin: origin, size: CGSize(width: size.width, height: size.height)), options: [.usesLineFragmentOrigin], attributes: textAttributes(annotation))
    }

    static func drawStep(_ annotation: Annotation) {
        let radius = annotation.stepRadius
        let circle = CGRect(x: annotation.start.x - radius, y: annotation.start.y - radius, width: radius * 2, height: radius * 2)
        withShadow(width: 2) {
            annotation.color.nsColor.setFill()
            NSBezierPath(ovalIn: circle).fill()
        }
        let label = "\(annotation.number)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: radius * 1.05, weight: .bold),
            .foregroundColor: annotation.color.contrastingText,
        ]
        let size = label.size(withAttributes: attributes)
        label.draw(at: CGPoint(x: annotation.start.x - size.width / 2, y: annotation.start.y - size.height / 2), withAttributes: attributes)
    }

    static func drawPixelated(rect: CGRect, baseImage: CGImage?) {
        let area = rect.integral
        guard area.width >= 2, area.height >= 2 else { return }
        guard let image = baseImage, let pixelated = pixelate(image, rect: area) else {
            // No source (live overlay): draw a solid redaction block.
            NSColor(hex: 0x5A5E66).setFill()
            NSBezierPath(rect: area).fill()
            return
        }
        let nsImage = NSImage(cgImage: pixelated, size: area.size)
        let hints: [NSImageRep.HintKey: Any] = [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)]
        nsImage.draw(in: area, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: hints)
    }

    /// Crops `rect` from the image and scales it down so it reads as blocks when drawn back up.
    static func pixelate(_ image: CGImage, rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let area = rect.intersection(bounds)
        guard !area.isNull, area.width >= 1, area.height >= 1, let cropped = image.cropping(to: area) else { return nil }
        // Blocks big enough that text inside a field is unreadable.
        let block = max(8, min(40, min(area.width, area.height) / 4))
        let smallWidth = max(1, Int(area.width / block))
        let smallHeight = max(1, Int(area.height / block))
        guard let context = CGContext(data: nil, width: smallWidth, height: smallHeight, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        return context.makeImage()
    }

    static func drawMagnifier(_ annotation: Annotation, baseImage: CGImage?) {
        let source = annotation.rect.integral
        guard source.width > 4, source.height > 4, let image = baseImage else { return }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let cropped = image.cropping(to: source.intersection(bounds)) else { return }
        let center = CGPoint(x: source.midX, y: source.midY)
        let diameter = max(source.width, source.height) * 2
        let circle = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        withShadow(width: 6) {
            NSColor.white.setFill()
            NSBezierPath(ovalIn: circle).fill()
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: circle).addClip()
        let scale = diameter / max(source.width, source.height)
        let drawRect = CGRect(x: center.x - source.width * scale / 2, y: center.y - source.height * scale / 2, width: source.width * scale, height: source.height * scale)
        let nsImage = NSImage(cgImage: cropped, size: source.size)
        nsImage.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])
        NSGraphicsContext.restoreGraphicsState()
        let border = NSBezierPath(ovalIn: circle)
        border.lineWidth = annotation.lineWidth
        annotation.color.nsColor.setStroke()
        border.stroke()
    }

    /// Environment badge in a corner of `bounds`. `scale` sizes it for the image.
    static func drawBadge(lines: [String], corner: BadgeCorner, bounds: CGRect, scale: CGFloat, in context: CGContext) {
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let fontSize = 11 * scale
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor(hex: 0xECEDEE),
        ]
        var width: CGFloat = 0
        var lineHeight: CGFloat = 0
        for line in lines {
            let size = (line as NSString).size(withAttributes: attributes)
            width = max(width, size.width)
            lineHeight = max(lineHeight, size.height)
        }
        let padding = 10 * scale
        let gap = 3 * scale
        let boxWidth = width + padding * 2
        let boxHeight = CGFloat(lines.count) * lineHeight + CGFloat(max(0, lines.count - 1)) * gap + padding * 2
        let margin = 12 * scale
        var origin = CGPoint(x: bounds.maxX - boxWidth - margin, y: bounds.minY + margin)
        switch corner {
        case .topRight:
            origin = CGPoint(x: bounds.maxX - boxWidth - margin, y: bounds.minY + margin)
        case .topLeft:
            origin = CGPoint(x: bounds.minX + margin, y: bounds.minY + margin)
        case .bottomRight:
            origin = CGPoint(x: bounds.maxX - boxWidth - margin, y: bounds.maxY - boxHeight - margin)
        case .bottomLeft:
            origin = CGPoint(x: bounds.minX + margin, y: bounds.maxY - boxHeight - margin)
        }
        let box = CGRect(origin: origin, size: CGSize(width: boxWidth, height: boxHeight))
        NSColor(hex: 0x1C1D20, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: box, xRadius: 8 * scale, yRadius: 8 * scale).fill()
        var y = box.minY + padding
        for line in lines {
            (line as NSString).draw(at: CGPoint(x: box.minX + padding, y: y), withAttributes: attributes)
            y += lineHeight + gap
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    static func distance(from point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 {
            return hypot(point.x - start.x, point.y - start.y)
        }
        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    /// Renders base image + annotations (+ optional badge) cropped to `crop`, at image pixel size.
    static func renderImage(base: CGImage, annotations: [Annotation], crop: CGRect?, badgeLines: [String]?, badgeCorner: BadgeCorner, badgeScale: CGFloat) -> CGImage? {
        let full = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let area = (crop ?? full).intersection(full).integral
        guard area.width >= 1, area.height >= 1 else { return nil }
        let width = Int(area.width)
        let height = Int(area.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: base.colorSpace ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Flip to y-down and shift so the crop origin lands at 0,0.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -area.minX, y: -area.minY)
        // Draw the base image right side up inside the flipped context.
        context.saveGState()
        context.translateBy(x: 0, y: full.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(base, in: full)
        context.restoreGState()

        draw(annotations, baseImage: base, in: context)
        if let lines = badgeLines {
            drawBadge(lines: lines, corner: badgeCorner, bounds: area, scale: badgeScale, in: context)
        }
        return context.makeImage()
    }
}
