import AVKit
import BugbearCore
import SwiftUI

struct VideoEditorView: View {
    let capture: Capture
    @State private var model: VideoEditorModel?
    @State private var switchingScreen = false

    var body: some View {
        Group {
            if let model = model {
                VideoEditorContent(model: model, switchingScreen: switchingScreen, onSelectScreen: { id in selectScreen(id) })
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .auroraBackground()
        .onAppear {
            if model == nil {
                model = VideoEditorModel(capture: capture)
            }
        }
        .onDisappear {
            model?.tearDown()
        }
    }

    /// Shows the clip from another display, or all displays side by side. Edits are kept.
    private func selectScreen(_ id: String) {
        guard let current = model, !switchingScreen, id != current.capture.selectedScreen else { return }
        switchingScreen = true
        Task {
            do {
                let updated = try await CaptureStore.shared.selectScreen(id, of: current.capture, framesPerSecond: AppState.shared.settings.framesPerSecond)
                current.tearDown()
                model = VideoEditorModel(capture: updated)
            } catch {
                AppState.shared.showError("Could not switch the screen: \(error.localizedDescription)")
            }
            switchingScreen = false
        }
    }
}

private struct VideoEditorContent: View {
    @Bindable var model: VideoEditorModel
    var switchingScreen: Bool
    var onSelectScreen: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                VideoStage(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.canvas)
                Divider().overlay(Theme.border)
                VideoSidebar(model: model)
            }
            Divider().overlay(Theme.border)
            transport
            Divider().overlay(Theme.border)
            TimelineEditor(model: model)
                .frame(height: 214)
        }
        .foregroundStyle(Theme.text)
        .padding(.top, 28)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        // Typing on the video took the focus; the editor's keys (Space, I, O, + and -) need it back.
        .onChange(of: model.editingTextID) { _, editing in
            if editing == nil {
                focused = true
            }
        }
        .onKeyPress(.space) {
            if isTypingText { return .ignored }
            model.togglePlay()
            return .handled
        }
        .background(DeleteKeyMonitor {
            if model.selection == nil {
                return false
            }
            model.deleteSelection()
            return true
        })
        .onKeyPress(keys: ["z"]) { press in
            if isTypingText || !press.modifiers.contains(.command) { return .ignored }
            if press.modifiers.contains(.shift) {
                model.redo()
            } else {
                model.undo()
            }
            return .handled
        }
        .onKeyPress(.delete) {
            if isTypingText { return .ignored }
            model.deleteSelection()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            if isTypingText { return .ignored }
            model.step(seconds: -1.0 / 30.0)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if isTypingText { return .ignored }
            model.step(seconds: 1.0 / 30.0)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "+=-_")) { press in
            if isTypingText { return .ignored }
            if press.characters == "+" || press.characters == "=" {
                model.changeSelectedOverlaySize(by: 1)
            } else {
                model.changeSelectedOverlaySize(by: -1)
            }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "ioIO")) { press in
            if isTypingText { return .ignored }
            if press.characters.lowercased() == "i" {
                model.setTrimStart(model.playhead)
            } else {
                model.setTrimEnd(model.playhead)
            }
            return .handled
        }
    }

    /// Shortcuts must not steal keys while a text field (an overlay's text) is being edited.
    private var isTypingText: Bool {
        return NSApp.keyWindow?.firstResponder is NSText
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 4) {
            // Without room for every title (a narrow window) the buttons show only their icons:
            // titles wrapped to two lines and pushed the screen picker out of the window.
            ViewThatFits(in: .horizontal) {
                toolGroup(showTitles: true)
                toolGroup(showTitles: false)
            }
            Spacer()
            screenPicker
            if model.isBuilding || switchingScreen {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    private func toolGroup(showTitles: Bool) -> some View {
        HStack(spacing: 4) {
            ToolButton(systemImage: "arrow.uturn.backward", help: "Undo the last change (⌘Z)") { model.undo() }
                .disabled(!model.canUndo)
            ToolButton(systemImage: "arrow.uturn.forward", help: "Redo what was undone (⇧⌘Z)") { model.redo() }
            Rectangle().fill(Theme.borderStrong).frame(width: 1, height: 22).padding(.horizontal, 6)
            ToolbarTextButton(showsTitle: showTitles, systemImage: "scissors", title: "Cut", help: "Cut the selected range (drag on the ruler first)") {
                model.cutSelection()
            }
            ToolbarTextButton(showsTitle: showTitles, systemImage: "arrow.right.to.line", title: "In", help: "Trim start at playhead (I)") {
                model.setTrimStart(model.playhead)
            }
            ToolbarTextButton(showsTitle: showTitles, systemImage: "arrow.left.to.line", title: "Out", help: "Trim end at playhead (O)") {
                model.setTrimEnd(model.playhead)
            }
            Rectangle().fill(Theme.borderStrong).frame(width: 1, height: 22).padding(.horizontal, 6)
            ToolbarTextButton(showsTitle: showTitles, systemImage: "textformat", title: "Text", help: "Drag on the video to place text", isSelected: model.tool == .text) {
                model.tool = model.tool == .text ? .select : .text
            }
            ToolbarTextButton(showsTitle: showTitles, systemImage: "arrow.up.right", title: "Arrow", help: "Drag on the video to draw an arrow", isSelected: model.tool == .arrow) {
                model.tool = model.tool == .arrow ? .select : .arrow
            }
            ToolbarTextButton(showsTitle: showTitles, systemImage: "rectangle", title: "Box", help: "Drag on the video to draw a box", isSelected: model.tool == .rectangle) {
                model.tool = model.tool == .rectangle ? .select : .rectangle
            }
            ToolbarTextButton(showsTitle: showTitles, systemImage: "eye.slash", title: "Blur", help: "Drag on the video to blur an area", isSelected: model.tool == .blur) {
                model.tool = model.tool == .blur ? .select : .blur
            }
            Rectangle().fill(Theme.borderStrong).frame(width: 1, height: 22).padding(.horizontal, 6)
            ToolbarTextButton(showsTitle: showTitles, systemImage: "tortoise", title: "Slow-mo", help: "Half speed for the selected range (or 3 s from the playhead)") {
                model.slowMotion()
            }
            ToolbarTextButton(showsTitle: showTitles, systemImage: "pause.rectangle", title: "Freeze", help: "Hold the current frame for 2 s") {
                model.freezeFrame()
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 44)
        .glassCard(cornerRadius: 14)
        .shadow(color: Color.black.opacity(0.35), radius: 14, y: 6)
    }

    /// Clips saved from several displays: pick one display or all of them side by side.
    @ViewBuilder
    private var screenPicker: some View {
        if let screens = model.capture.screens, screens.count > 1 {
            HStack(spacing: 8) {
                Image(systemName: "display.2")
                    .foregroundStyle(Theme.textSecondary)
                Picker(selection: Binding(get: { model.capture.selectedScreen ?? screens[0].id }, set: { id in onSelectScreen(id) })) {
                    ForEach(screens) { screen in
                        Text(screen.name).tag(screen.id)
                            .accessibilityLabel("Screen: \(screen.name)")
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(switchingScreen)
            }
            .tip("Which screen is in the clip. Edits stay when you switch.")
            .padding(.trailing, 8)
        }
    }

    // MARK: Transport

    private var transport: some View {
        HStack(spacing: 12) {
            ToolButton(systemImage: "backward.fill", help: "Back 5 seconds") { model.step(seconds: -5) }
            Button {
                model.togglePlay()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.window)
                    .frame(width: 34, height: 34)
                    .background(Theme.text)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            ToolButton(systemImage: "forward.fill", help: "Forward 5 seconds") { model.step(seconds: 5) }
            HStack(spacing: 4) {
                Text(TimeFormat.clockPrecise(model.outputPlayhead))
                Text("/ " + TimeFormat.clockPrecise(model.outputDuration)).foregroundStyle(Theme.textSecondary)
            }
            .font(.system(size: 12, design: .monospaced))

            if let message = model.message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.success)
                    .lineLimit(1)
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        model.message = nil
                    }
            }
            Spacer()
            if let progress = model.exportProgress {
                ProgressView(value: progress).frame(width: 120)
                Text("\(Int(progress * 100))%").font(.system(size: 12, design: .monospaced))
            }
            VideoDragOut(model: model)
            Button("Save to folder") { Task { await model.saveToFolder() } }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.exportProgress != nil)
            Button("Copy \(model.project.format.rawValue)") { Task { await model.copyFile() } }
                .buttonStyle(AccentButtonStyle())
                .disabled(model.exportProgress != nil)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }
}

/// The field for typing a text mark right on the video. An AppKit field that takes the keyboard
/// itself as soon as it is shown: with a SwiftUI field the focus did not always move, and the
/// letters reached the editor's shortcuts (O trimmed, Space played) instead of the text.
private struct InlineTextField: NSViewRepresentable {
    var text: String
    var textColor: NSColor
    var onChange: (String) -> Void
    /// Return.
    var onCommit: () -> Void
    /// The field lost the keyboard (a click somewhere else).
    var onEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        field.textColor = textColor
        field.placeholderString = "Type…"
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Text on the video")
        // The click that placed the text then focuses the editor itself (it is focusable for its
        // shortcuts), after this field asked: so it asks again until it has the keyboard.
        for delay in [0.0, 0.15, 0.35, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if field.currentEditor() == nil, let window = field.window {
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(field)
                }
            }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.textColor = textColor
        // Only from outside (the side panel); while typing the field holds the newest text.
        if field.currentEditor() == nil && field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineTextField
        private var committed = false

        init(_ parent: InlineTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.onChange(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:)) {
                committed = true
                parent.onCommit()
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            if committed { return }
            parent.onEnd()
        }
    }
}

/// The arrow being dragged on the video: a line with a head at the end.
private struct ArrowPreview: Shape {
    var start: CGPoint
    var end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let head: CGFloat = 16
        path.move(to: end)
        path.addLine(to: CGPoint(x: end.x - head * cos(angle - .pi / 6), y: end.y - head * sin(angle - .pi / 6)))
        path.move(to: end)
        path.addLine(to: CGPoint(x: end.x - head * cos(angle + .pi / 6), y: end.y - head * sin(angle + .pi / 6)))
        return path
    }
}

private struct ToolbarTextButton: View {
    var showsTitle = true
    let systemImage: String
    let title: String
    let help: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 13))
                if showsTitle {
                    Text(title).font(.system(size: 13)).lineLimit(1).fixedSize()
                }
            }
            .foregroundStyle(isSelected ? Theme.accentSoft : Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(isSelected ? Theme.controlSelected : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .tip(help)
    }
}

private struct VideoDragOut: View {
    let model: VideoEditorModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.draw")
            Text("Drag")
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .contentShape(Rectangle())
        .tip("Drag the original clip into another app. Use Copy or Save for the edited version.")
        .onDrag {
            return NSItemProvider(contentsOf: model.capture.mediaURL) ?? NSItemProvider()
        }
    }
}

// MARK: - Video stage

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(hex: 0x131416).cgColor
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }
}

/// The player plus a layer for drawing new overlays and moving the selected one.
private struct VideoStage: View {
    @Bindable var model: VideoEditorModel
    @State private var aspect: CGFloat = 16.0 / 9.0
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var moveOriginal: VideoOverlay?

    var body: some View {
        GeometryReader { proxy in
            let videoRect = fittedRect(in: proxy.size)
            ZStack(alignment: .topLeading) {
                PlayerView(player: model.player)
                    .frame(width: proxy.size.width, height: proxy.size.height)

                // Outline of the selected overlay when it is on screen right now.
                if let overlay = model.selectedOverlay, overlay.span.contains(model.playhead) {
                    let rect = denormalize(markBox(overlay), in: videoRect)
                    Rectangle()
                        .stroke(Theme.link, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(width: max(rect.width, 12), height: max(rect.height, 12))
                        .offset(x: rect.minX - 6, y: rect.minY - 6)
                        .padding(6)
                        .allowsHitTesting(false)
                }

                if let start = dragStart, let current = dragCurrent, model.tool != .select {
                    // While dragging: the arrow as it will be, a dashed area for a box or blur.
                    if model.tool == .arrow {
                        ArrowPreview(start: start, end: current)
                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .allowsHitTesting(false)
                    } else {
                        let rect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y))
                        Rectangle()
                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .background(Theme.accent.opacity(0.08))
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .allowsHitTesting(false)
                    }
                }

                // Typing a text mark right on the video.
                if let id = model.editingTextID, let overlay = model.project.overlays.first(where: { item in item.id == id }) {
                    let point = denormalize(CGRect(origin: overlay.start, size: .zero), in: videoRect).origin
                    InlineTextField(
                        text: overlay.text,
                        textColor: overlay.color.contrastingText,
                        onChange: { value in model.setText(value, of: id) },
                        onCommit: { model.finishTextEditing() },
                        onEnd: { model.finishTextEditing(removingEmpty: false) }
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(width: 240, height: 30)
                    .background(overlay.color.color.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .offset(x: min(point.x, max(0, proxy.size.width - 240)), y: point.y)
                }

                if model.tool != .select {
                    Text("Drag on the video to add \(model.tool.overlayKind?.title.lowercased() ?? "")")
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: 0x1C1D20, alpha: 0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        handleDrag(value, videoRect: videoRect)
                    }
                    .onEnded { value in
                        finishDrag(value, videoRect: videoRect)
                    }
            )
            .onTapGesture(count: 1, coordinateSpace: .local) { location in
                handleClick(at: location, videoRect: videoRect)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { rememberStage(proxy) }
                    .onChange(of: proxy.size) { rememberStage(proxy) }
                    .onChange(of: aspect) { rememberStage(proxy) }
            }
        )
        .task {
            if let track = try? await model.asset.loadTracks(withMediaType: .video).first,
               let size = try? await track.load(.naturalSize), size.height > 0 {
                aspect = size.width / size.height
            }
        }
    }

    private func rememberStage(_ proxy: GeometryProxy) {
        let stage = proxy.frame(in: .global)
        let video = fittedRect(in: proxy.size)
        model.stageVideoRect = CGRect(x: stage.minX + video.minX, y: stage.minY + video.minY, width: video.width, height: video.height)
    }

    private func fittedRect(in size: CGSize) -> CGRect {
        let containerAspect = size.width / max(size.height, 1)
        if containerAspect > aspect {
            let width = size.height * aspect
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        }
        let height = size.width / aspect
        return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
    }

    private func normalize(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        let x = (point.x - rect.minX) / rect.width
        let y = (point.y - rect.minY) / rect.height
        return CGPoint(x: max(0, min(1, x)), y: max(0, min(1, y)))
    }

    /// One click, without waiting to see if a second one follows (a double-click gesture made
    /// every click late): typing ends, Text places text, a click on a mark picks it and a second
    /// click on picked text types into it, anywhere else the video plays or pauses.
    private func handleClick(at location: CGPoint, videoRect: CGRect) {
        if model.editingTextID != nil {
            model.finishTextEditing()
            return
        }
        if model.tool == .text {
            let point = normalize(location, in: videoRect)
            model.addOverlay(kind: .text, start: point, end: point)
            return
        }
        if model.tool != .select {
            model.message = "Drag on the video to draw the \(model.tool.overlayKind?.title.lowercased() ?? "mark")"
            return
        }
        for overlay in model.project.overlays.reversed() where overlay.span.contains(model.playhead) {
            let box = denormalize(markBox(overlay), in: videoRect).insetBy(dx: -10, dy: -10)
            if !box.contains(location) { continue }
            if overlay.kind == .text && model.selection == .overlay(overlay.id) {
                model.beginTextEditing(overlay.id)
            } else {
                model.selection = .overlay(overlay.id)
            }
            return
        }
        model.togglePlay()
    }

    /// The area a mark covers in 0…1 frame coordinates; text gets a small box at its start.
    private func markBox(_ overlay: VideoOverlay) -> CGRect {
        if overlay.kind == .text {
            return VideoOverlay.textBox(overlay)
        }
        return overlay.rect
    }

    private func denormalize(_ rect: CGRect, in video: CGRect) -> CGRect {
        return CGRect(x: video.minX + rect.minX * video.width, y: video.minY + rect.minY * video.height, width: rect.width * video.width, height: rect.height * video.height)
    }

    private func handleDrag(_ value: DragGesture.Value, videoRect: CGRect) {
        if model.tool != .select {
            if dragStart == nil {
                dragStart = value.startLocation
            }
            dragCurrent = value.location
            return
        }
        // Move the selected overlay: only one on screen now, and only when the drag starts on it.
        // Before, any drag moved it, also while it was not in this frame, and it slid off the video.
        if moveOriginal == nil {
            guard let overlay = model.selectedOverlay, overlay.span.contains(model.playhead) else { return }
            let box = denormalize(markBox(overlay), in: videoRect).insetBy(dx: -12, dy: -12)
            if !box.contains(value.startLocation) { return }
            moveOriginal = overlay
            model.checkpoint()
        }
        guard let original = moveOriginal else { return }
        let box = markBox(original)
        let shift = MarkMove.keepInside(minX: box.minX, minY: box.minY, maxX: box.maxX, maxY: box.maxY, dx: value.translation.width / videoRect.width, dy: value.translation.height / videoRect.height)
        var moved = original
        moved.start = CGPoint(x: original.start.x + shift.dx, y: original.start.y + shift.dy)
        moved.end = CGPoint(x: original.end.x + shift.dx, y: original.end.y + shift.dy)
        model.updateOverlay(moved)
    }

    private func finishDrag(_ value: DragGesture.Value, videoRect: CGRect) {
        defer {
            dragStart = nil
            dragCurrent = nil
            moveOriginal = nil
        }
        guard let kind = model.tool.overlayKind else { return }
        let start = normalize(value.startLocation, in: videoRect)
        let end = normalize(value.location, in: videoRect)
        if kind != .text && hypot(end.x - start.x, end.y - start.y) < 0.01 { return }
        model.addOverlay(kind: kind, start: start, end: end)
    }
}
