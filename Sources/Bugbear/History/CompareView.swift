import AVKit
import AppKit
import BugbearCore
import SwiftUI

/// Before and after: two screenshots (side by side, a slider, or the changes boxed in red),
/// or two clips playing in sync.
struct CompareView: View {
    let before: Capture
    let after: Capture

    var body: some View {
        if before.kind == .screenshot && after.kind == .screenshot {
            ScreenshotCompareView(before: before, after: after)
        } else {
            VideoCompareView(before: before, after: after)
        }
    }
}

enum CompareMode: String, CaseIterable, Identifiable {
    case sideBySide = "Side by side"
    case slider = "Slider"
    case changes = "Changes"

    var id: String { rawValue }
}

/// Renders both images at the same size and finds what changed.
enum ScreenshotComparison {
    struct Output {
        var before: CGImage
        var after: CGImage
        var result: PixelDiff.Result
        /// Scale from diff pixels to the after image's pixels.
        var scale: CGFloat
    }

    @MainActor
    static func make(before: Capture, after: Capture) -> Output? {
        guard let first = ScreenshotDocument(capture: before, forEditing: false)?.render(), let second = ScreenshotDocument(capture: after, forEditing: false)?.render() else { return nil }
        // Diff at up to 1600 px wide: fast, and fine enough to box changes.
        let diffWidth = min(1600, second.width)
        let diffScale = CGFloat(diffWidth) / CGFloat(second.width)
        let diffHeight = Int(CGFloat(second.height) * diffScale)
        guard let firstPixels = rgba(first, width: diffWidth, height: diffHeight), let secondPixels = rgba(second, width: diffWidth, height: diffHeight) else { return nil }
        let result = PixelDiff.compare(width: diffWidth, height: diffHeight, first: firstPixels, second: secondPixels)
        return Output(before: first, after: second, result: result, scale: 1 / diffScale)
    }

    static func rgba(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        if !drawn { return nil }
        return pixels
    }

    /// After image with every change boxed in red and the rest slightly dimmed.
    static func changesImage(_ output: Output) -> CGImage? {
        // Nothing changed: show the after image as it is, not dimmed.
        if output.result.regions.isEmpty {
            return output.after
        }
        let width = output.after.width
        let height = output.after.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(output.after, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0, alpha: 0.35))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let line = max(3, CGFloat(width) / 500)
        for region in output.result.regions {
            // Diff rects are top-left based; Core Graphics is bottom-left.
            let rect = CGRect(x: CGFloat(region.x) * output.scale, y: CGFloat(height) - CGFloat(region.y + region.height) * output.scale, width: CGFloat(region.width) * output.scale, height: CGFloat(region.height) * output.scale)
            context.saveGState()
            context.clip(to: rect)
            context.draw(output.after, in: CGRect(x: 0, y: 0, width: width, height: height))
            context.restoreGState()
            context.setStrokeColor(CGColor(red: 1, green: 0.27, blue: 0.2, alpha: 1))
            context.setLineWidth(line)
            context.stroke(rect.insetBy(dx: -line, dy: -line))
        }
        return context.makeImage()
    }

    /// Before | After with labels, for pasting into a ticket.
    static func sideBySideImage(_ output: Output, changes: CGImage?) -> CGImage? {
        let right = changes ?? output.after
        let height = max(output.before.height, right.height)
        let gap = 40
        let label = 70
        let width = output.before.width + right.width + gap * 3
        guard let context = CGContext(data: nil, width: width, height: height + label + gap, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height + label + gap))
        context.draw(output.before, in: CGRect(x: gap, y: gap, width: output.before.width, height: output.before.height))
        context.draw(right, in: CGRect(x: gap * 2 + output.before.width, y: gap, width: right.width, height: right.height))
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 40, weight: .bold), .foregroundColor: NSColor(hex: 0x1C1D20)]
        ("Before" as NSString).draw(at: CGPoint(x: gap, y: height + gap + 10), withAttributes: attributes)
        ("After" as NSString).draw(at: CGPoint(x: gap * 2 + output.before.width, y: height + gap + 10), withAttributes: attributes)
        NSGraphicsContext.current = previous
        return context.makeImage()
    }
}

struct ScreenshotCompareView: View {
    let before: Capture
    let after: Capture
    @State private var mode = CompareMode.changes
    @State private var split: CGFloat = 0.5
    @State private var output: ScreenshotComparison.Output?
    @State private var changes: CGImage?
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                PillPicker(options: CompareMode.allCases, selection: $mode) { value in value.rawValue }
                    .frame(width: 360)
                    .tip("How to compare: side by side, a before/after slider, or only the changed areas highlighted")
                if let current = output {
                    Text(summary(current.result)).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let text = message {
                    Text(text).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                Button("Copy image") { copy() }
                    .buttonStyle(AccentButtonStyle(isEnabled: output != nil))
                    .disabled(output == nil)
                    .tip("Copy the comparison as an image to paste into a bug report")
            }
            .padding(.horizontal, 16)
            .padding(.top, 36)
            .padding(.bottom, 12)
            Divider().overlay(Theme.border)
            if let current = output {
                content(current)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.canvas)
            } else {
                Text("Loading…").foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(Theme.text)
        .auroraBackground()
        .task {
            let made = ScreenshotComparison.make(before: before, after: after)
            output = made
            if let current = made {
                changes = ScreenshotComparison.changesImage(current)
            }
        }
    }

    private func summary(_ result: PixelDiff.Result) -> String {
        if result.regions.isEmpty {
            return "No visible differences"
        }
        let percent = String(format: "%.1f", result.changedShare * 100)
        if result.regions.count == 1 {
            return "1 changed area · \(percent)% of pixels"
        }
        return "\(result.regions.count) changed areas · \(percent)% of pixels"
    }

    @ViewBuilder
    private func content(_ current: ScreenshotComparison.Output) -> some View {
        switch mode {
        case .sideBySide:
            HStack(spacing: 16) {
                labeled("Before", current.before)
                labeled("After", current.after)
            }
        case .slider:
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    picture(current.after)
                    picture(current.before)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: geometry.size.width * split)
                        }
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: 3)
                        .offset(x: geometry.size.width * split - 1.5)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    split = max(0, min(1, value.location.x / geometry.size.width))
                })
                .overlay(alignment: .top) {
                    Text("Drag: before on the left, after on the right")
                        .font(.system(size: 11))
                        .padding(6)
                        .background(Color.black.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(8)
                }
            }
        case .changes:
            HStack(spacing: 16) {
                labeled("Before", current.before)
                if let boxed = changes {
                    labeled("After · changes boxed", boxed)
                }
            }
        }
    }

    private func picture(_ image: CGImage) -> some View {
        Image(nsImage: NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height)))
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    private func labeled(_ title: String, _ image: CGImage) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            picture(image)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copy() {
        guard let current = output else { return }
        var boxed: CGImage? = nil
        if mode == .changes {
            boxed = changes
        }
        guard let image = ScreenshotComparison.sideBySideImage(current, changes: boxed) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))])
        message = "Copied Before | After"
    }
}

/// Two clips side by side with one play button and one scrubber.
struct VideoCompareView: View {
    let before: Capture
    let after: Capture
    @State private var firstPlayer = AVPlayer()
    @State private var secondPlayer = AVPlayer()
    @State private var position: Double = 0
    @State private var isPlaying = false

    private var longest: Double {
        return max(before.duration, after.duration, 0.1)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                clip("Before", firstPlayer)
                clip("After", secondPlayer)
            }
            .padding(16)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
            HStack(spacing: 12) {
                Button {
                    togglePlay()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill").frame(width: 24)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityLabel(isPlaying ? "Pause both" : "Play both")
                .tip("Play or pause both clips together (Space)")
                Slider(value: Binding(get: { position }, set: { value in seek(value) }), in: 0...longest)
                    .accessibilityLabel("Position")
                    .tip("Scrub both clips to the same moment")
                Text("\(TimeFormat.clock(position)) / \(TimeFormat.clock(longest))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(12)
        }
        .foregroundStyle(Theme.text)
        .auroraBackground()
        .onAppear {
            firstPlayer.replaceCurrentItem(with: AVPlayerItem(url: before.mediaURL))
            secondPlayer.replaceCurrentItem(with: AVPlayerItem(url: after.mediaURL))
        }
        .onDisappear {
            firstPlayer.pause()
            secondPlayer.pause()
        }
        .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in
            if isPlaying {
                position = max(firstPlayer.currentTime().seconds, secondPlayer.currentTime().seconds)
                if position >= longest - 0.05 {
                    isPlaying = false
                }
            }
        }
    }

    private func clip(_ title: String, _ player: AVPlayer) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            // Without the player's own buttons: "Play both" and the slider keep the two clips together.
            PlayerView(player: player)
        }
    }

    private func togglePlay() {
        if isPlaying {
            firstPlayer.pause()
            secondPlayer.pause()
        } else {
            if position >= longest - 0.05 {
                seek(0)
            }
            firstPlayer.play()
            secondPlayer.play()
        }
        isPlaying.toggle()
    }

    private func seek(_ seconds: Double) {
        position = seconds
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        firstPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        secondPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
