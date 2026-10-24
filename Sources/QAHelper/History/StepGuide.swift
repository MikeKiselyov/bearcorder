import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Several screenshots (with their arrows and boxes) as one numbered guide: "1. Open settings, 2. …".
@MainActor
@Observable
final class StepGuideModel {
    struct Step: Identifiable {
        let id = UUID()
        var image: CGImage
        var caption: String
    }

    var title = "How to reproduce"
    var steps: [Step] = []
    var message: String?

    init(captures: [Capture]) {
        // Oldest first: the order things happened in.
        let ordered = captures.sorted { first, second in first.createdAt < second.createdAt }
        for capture in ordered {
            guard let document = ScreenshotDocument(capture: capture), let image = document.render() else { continue }
            steps.append(Step(image: image, caption: ""))
        }
    }

    func move(_ index: Int, by offset: Int) {
        let target = index + offset
        if target < 0 || target >= steps.count { return }
        steps.swapAt(index, target)
    }

    func remove(_ index: Int) {
        steps.remove(at: index)
    }

    private var blocks: [(image: CGImage, caption: String)] {
        var result: [(image: CGImage, caption: String)] = []
        for step in steps {
            result.append((image: step.image, caption: step.caption))
        }
        return result
    }

    func copyImage() {
        guard let image = StepGuideRenderer.longImage(title: title, steps: blocks) else { return }
        let picture = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([picture])
        message = "Copied the guide as one image"
    }

    func save(asPDF: Bool) {
        let panel = NSSavePanel()
        if asPDF {
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "steps.pdf"
        } else {
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "steps.png"
        }
        panel.directoryURL = AppSettings.shared.outputFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var saved = false
        if asPDF {
            saved = StepGuideRenderer.writePDF(title: title, steps: blocks, to: url)
        } else if let image = StepGuideRenderer.longImage(title: title, steps: blocks) {
            ImageFiles.write(image, to: url, type: "public.png")
            saved = true
        }
        if saved {
            message = "Saved \(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            message = "Could not save the guide"
        }
    }
}

/// Draws the guide: a title, then for every step a number, its caption and the screenshot.
enum StepGuideRenderer {
    static let width: CGFloat = 1400
    static let padding: CGFloat = 56
    static let titleFont = NSFont.systemFont(ofSize: 40, weight: .bold)
    static let captionFont = NSFont.systemFont(ofSize: 26, weight: .medium)
    static let accent = NSColor(hex: 0xFF6B4A)

    struct Block {
        var number: Int
        var image: CGImage
        var caption: String
        var imageSize: CGSize
        var captionHeight: CGFloat

        var height: CGFloat {
            return max(48, captionHeight) + 20 + imageSize.height
        }
    }

    static func layout(_ steps: [(image: CGImage, caption: String)]) -> [Block] {
        let contentWidth = width - padding * 2
        var blocks: [Block] = []
        for (index, step) in steps.enumerated() {
            let scale = min(1, contentWidth / CGFloat(step.image.width))
            let size = CGSize(width: CGFloat(step.image.width) * scale, height: CGFloat(step.image.height) * scale)
            let caption = captionText(step.caption, number: index + 1)
            let bounds = (caption as NSString).boundingRect(with: CGSize(width: contentWidth - 70, height: 10_000), options: [.usesLineFragmentOrigin], attributes: [.font: captionFont])
            blocks.append(Block(number: index + 1, image: step.image, caption: caption, imageSize: size, captionHeight: ceil(bounds.height)))
        }
        return blocks
    }

    static func captionText(_ caption: String, number: Int) -> String {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Step \(number)"
        }
        return trimmed
    }

    static func titleHeight(_ title: String) -> CGFloat {
        if title.trimmingCharacters(in: .whitespaces).isEmpty { return 0 }
        let bounds = (title as NSString).boundingRect(with: CGSize(width: width - padding * 2, height: 10_000), options: [.usesLineFragmentOrigin], attributes: [.font: titleFont])
        return ceil(bounds.height) + 36
    }

    /// One tall PNG-ready image with every step.
    static func longImage(title: String, steps: [(image: CGImage, caption: String)]) -> CGImage? {
        let blocks = layout(steps)
        if blocks.isEmpty { return nil }
        var height = padding + titleHeight(title)
        for block in blocks {
            height += block.height + 48
        }
        height += padding - 48
        let size = CGSize(width: width, height: height)
        return drawImage(size: size) { context in
            var y = padding
            y = drawTitle(title, at: y, in: context)
            for block in blocks {
                draw(block, at: y)
                y += block.height + 48
            }
        }
    }

    /// One page per step; the title sits on the first page.
    static func writePDF(title: String, steps: [(image: CGImage, caption: String)], to url: URL) -> Bool {
        let blocks = layout(steps)
        guard !blocks.isEmpty, let consumer = CGDataConsumer(url: url as CFURL) else { return false }
        var firstBox = CGRect(x: 0, y: 0, width: width, height: 800)
        guard let pdf = CGContext(consumer: consumer, mediaBox: &firstBox, nil) else { return false }
        for (index, block) in blocks.enumerated() {
            var top = padding
            if index == 0 {
                top += titleHeight(title)
            }
            var box = CGRect(x: 0, y: 0, width: width, height: top + block.height + padding)
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary
            pdf.beginPDFPage(info)
            pdf.translateBy(x: 0, y: box.height)
            pdf.scaleBy(x: 1, y: -1)
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: true)
            NSColor.white.setFill()
            box.fill()
            var y = padding
            if index == 0 {
                y = drawTitle(title, at: y, in: pdf)
            }
            draw(block, at: y)
            NSGraphicsContext.current = previous
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return true
    }

    private static func drawImage(size: CGSize, content: (CGContext) -> Void) -> CGImage? {
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        NSColor.white.setFill()
        CGRect(origin: .zero, size: size).fill()
        content(context)
        NSGraphicsContext.current = previous
        return context.makeImage()
    }

    private static func drawTitle(_ title: String, at y: CGFloat, in context: CGContext) -> CGFloat {
        let height = titleHeight(title)
        if height == 0 { return y }
        let rect = CGRect(x: padding, y: y, width: width - padding * 2, height: height)
        (title as NSString).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: [.font: titleFont, .foregroundColor: NSColor(hex: 0x1C1D20)])
        return y + height
    }

    private static func draw(_ block: Block, at y: CGFloat) {
        let circle = CGRect(x: padding, y: y, width: 48, height: 48)
        accent.setFill()
        NSBezierPath(ovalIn: circle).fill()
        let number = "\(block.number)" as NSString
        let numberAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 24, weight: .bold), .foregroundColor: NSColor.white]
        let numberSize = number.size(withAttributes: numberAttributes)
        number.draw(at: CGPoint(x: circle.midX - numberSize.width / 2, y: circle.midY - numberSize.height / 2), withAttributes: numberAttributes)

        let captionRect = CGRect(x: padding + 70, y: y + max(0, (48 - block.captionHeight) / 2), width: width - padding * 2 - 70, height: block.captionHeight)
        (block.caption as NSString).draw(with: captionRect, options: [.usesLineFragmentOrigin], attributes: [.font: captionFont, .foregroundColor: NSColor(hex: 0x1C1D20)])

        let imageRect = CGRect(x: padding, y: y + max(48, block.captionHeight) + 20, width: block.imageSize.width, height: block.imageSize.height)
        NSImage(cgImage: block.image, size: imageRect.size).draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSColor(hex: 0xD9DBE0).setStroke()
        let border = NSBezierPath(rect: imageRect.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()
    }
}

struct StepGuideView: View {
    @State var model: StepGuideModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Title", text: $model.title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: 420)
                Spacer()
                if let message = model.message {
                    Text(message).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                Button("Copy image") { model.copyImage() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Save PDF…") { model.save(asPDF: true) }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Save PNG…") { model.save(asPDF: false) }
                    .buttonStyle(AccentButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 36)
            .padding(.bottom, 12)
            Divider().overlay(Theme.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(model.steps.enumerated()), id: \.element.id) { index, step in
                        stepRow(index: index, step: step)
                    }
                    if model.steps.isEmpty {
                        Text("No screenshots to put in the guide.").foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(16)
            }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.window)
    }

    private func stepRow(index: Int, step: StepGuideModel.Step) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(index + 1)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 30, height: 30)
                .background(Theme.accent)
                .clipShape(Circle())
            Image(nsImage: NSImage(cgImage: step.image, size: CGSize(width: step.image.width, height: step.image.height)))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 260, height: 150)
                .background(Theme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 8) {
                TextField("What to do in this step, e.g. Open Settings → Billing", text: Binding(get: {
                    if index < model.steps.count { return model.steps[index].caption }
                    return ""
                }, set: { text in
                    if index < model.steps.count { model.steps[index].caption = text }
                }), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                HStack(spacing: 10) {
                    Button { model.move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                        .disabled(index == 0)
                        .help("Move up")
                    Button { model.move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                        .disabled(index == model.steps.count - 1)
                        .help("Move down")
                    Button(role: .destructive) { model.remove(index) } label: { Image(systemName: "trash") }
                        .help("Remove from the guide")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
