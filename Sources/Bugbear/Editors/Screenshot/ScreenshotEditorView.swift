import AppKit
import BugbearCore
import SwiftUI
import UniformTypeIdentifiers

struct ScreenshotEditorView: View {
    let capture: Capture
    @State private var document: ScreenshotDocument?
    @State private var switchingScreen = false

    var body: some View {
        Group {
            if let document = document {
                ScreenshotEditorContent(document: document, switchingScreen: switchingScreen, onSelectScreen: { id in selectScreen(id) })
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.exclamationmark").font(.system(size: 32))
                    Text("Could not open this screenshot").foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.window)
        .onAppear {
            if document == nil {
                let opened = ScreenshotDocument(capture: capture)
                if AppState.shared.justCopiedScreenshot == capture.id {
                    opened?.message = "Copied to the clipboard · ⌘V to paste"
                }
                document = opened
            }
        }
    }

    /// Shows another display, or all of them side by side. Each picture keeps its own marks.
    private func selectScreen(_ id: String) {
        guard let current = document, !switchingScreen, id != current.capture.selectedScreen else { return }
        switchingScreen = true
        current.saveProject()
        Task {
            do {
                let updated = try await CaptureStore.shared.selectScreen(id, of: current.capture, framesPerSecond: AppState.shared.settings.framesPerSecond)
                document = ScreenshotDocument(capture: updated)
            } catch {
                AppState.shared.showError("Could not switch the screen: \(error.localizedDescription)")
            }
            switchingScreen = false
        }
    }
}

private struct ScreenshotEditorContent: View {
    @Bindable var document: ScreenshotDocument
    var switchingScreen: Bool
    var onSelectScreen: (String) -> Void

    static let editorTools: [AnnotationTool] = [.select, .arrow, .rectangle, .ellipse, .line, .highlighter, .pen, .text, .step, .blur, .magnifier, .crop]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Theme.border)
            HStack(spacing: 0) {
                AnnotationCanvas(document: document)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) { cropHint }
                    .background(DeleteKeyMonitor {
                        if document.selectedId == nil {
                            return false
                        }
                        document.deleteSelected()
                        return true
                    })
                Divider().overlay(Theme.border)
                sidebar
            }
            Divider().overlay(Theme.border)
            bottomBar
        }
        .foregroundStyle(Theme.text)
        .padding(.top, 28)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 2) {
            ToolButton(systemImage: "arrow.uturn.backward", help: "Undo the last change (⌘Z)") { document.undo() }
                .disabled(!document.canUndo)
            ToolButton(systemImage: "arrow.uturn.forward", help: "Redo what was undone (⇧⌘Z)") { document.redo() }
                .disabled(!document.canRedo)

            Rectangle().fill(Theme.borderStrong).frame(width: 1, height: 24).padding(.horizontal, 8)

            ForEach(Self.editorTools) { tool in
                ToolButton(systemImage: tool.symbol, help: "\(tool.title) (\(String(tool.keyboardShortcut ?? " ").uppercased())): \(tool.purpose)", isSelected: document.tool == tool) {
                    document.tool = tool
                }
            }
            ToolButton(systemImage: "rectangle.split.2x1", help: "Combine with another screenshot: places other images to the right") {
                combine()
            }

            Rectangle().fill(Theme.borderStrong).frame(width: 1, height: 24).padding(.horizontal, 8)

            ColorPalette(selection: document.color, swatchSize: 18) { color in
                document.color = color
                document.applyStyleToSelection()
            }

            Rectangle().fill(Theme.borderStrong).frame(width: 1, height: 24).padding(.horizontal, 8)

            HStack(spacing: 6) {
                FillToggle(isFilled: document.isFilled, isEnabled: document.fillTarget != nil) { filled in
                    document.setFilled(filled)
                }
                SizeStepper(value: "\(Int(document.stroke.width))", name: "line") { direction in
                    document.stroke = document.stroke.stepped(direction)
                    document.applySizeToSelection()
                }
                SizeStepper(value: "\(Int(document.textPoints))", name: "text") { direction in
                    document.textPoints = TextSizes.stepped(from: document.textPoints, direction)
                    document.applySizeToSelection()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    @ViewBuilder
    private var cropHint: some View {
        if document.tool == .crop {
            HStack(spacing: 10) {
                Text("Drag the edges or corners · drag inside to move · Enter to apply · Esc to leave").font(.system(size: 12))
                if document.crop != nil {
                    Button("Reset crop") { document.setCrop(nil) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.link)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(hex: 0x1C1D20, alpha: 0.92))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.top, 10)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                environmentPanel
                Divider().overlay(Theme.border)
                presetPanel
                Divider().overlay(Theme.border)
                if let selected = document.selected {
                    inspector(selected)
                    Divider().overlay(Theme.border)
                }
                layersPanel
            }
        }
        .frame(width: 270)
        .background(Theme.window)
    }

    private var environmentPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Environment")
                Spacer()
                Button("Copy") { document.copyEnvironment() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.link)
            }
            CopyReportButton(help: "Steps from your clicks and keys in the last minute, environment and the saved file") { format in
                document.copyBugReport(format: format)
            }
            .frame(maxWidth: .infinity)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
                ForEach(Array(document.capture.environment.rows().enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.label).foregroundStyle(Theme.textSecondary)
                        Text(row.value)
                            .textSelection(.enabled)
                            .lineLimit(3)
                    }
                    .font(.system(size: 12))
                }
            }
            SettingToggle(title: "Overlay on image", isOn: Binding(get: { document.showBadge }, set: { value in
                document.showBadge = value
                document.saveProject()
            }))
            if document.showBadge {
                Picker("Corner", selection: Binding(get: { document.badgeCorner }, set: { value in
                    document.badgeCorner = value
                    document.saveProject()
                })) {
                    ForEach(BadgeCorner.allCases) { corner in
                        Text(corner.title).tag(corner)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 12))
            }
        }
        .padding(16)
    }

    private var presetPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Style preset")
            Menu {
                ForEach(StylePreset.all) { preset in
                    Button(preset.name) { document.applyPreset(preset) }
                }
            } label: {
                HStack {
                    Text(currentPresetName).font(.system(size: 13))
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 10))
                }
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Theme.control)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(16)
    }

    private var currentPresetName: String {
        for preset in StylePreset.all where preset.color == document.color && preset.stroke == document.stroke {
            return preset.name
        }
        return "Custom"
    }

    private func inspector(_ annotation: Annotation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Selected · \(annotation.tool.title)")
            if annotation.tool == .text {
                TextField("Text", text: Binding(get: {
                    document.selected?.text ?? ""
                }, set: { value in
                    document.setText(value, for: annotation.id)
                }))
                .textFieldStyle(.roundedBorder)
            }
            if annotation.tool == .step {
                Stepper("Number \(annotation.number)", value: Binding(get: {
                    document.selected?.number ?? 1
                }, set: { value in
                    var updated = annotation
                    updated.number = max(1, value)
                    document.checkpoint()
                    document.replace(updated)
                    document.saveProject()
                }), in: 1...99)
                .font(.system(size: 12))
            }
            Button(role: .destructive) {
                document.deleteSelected()
            } label: {
                Label("Delete", systemImage: "trash").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accentSoft)
        }
        .padding(16)
    }

    private var layersPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Layers")
            if document.annotations.isEmpty {
                Text("Pick a tool above and draw on the screenshot.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(document.annotations.reversed()) { annotation in
                let isSelected = annotation.id == document.selectedId
                HStack(spacing: 10) {
                    Image(systemName: annotation.tool.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(annotation.color.color)
                        .frame(width: 16)
                    Text(annotation.layerName).font(.system(size: 13)).lineLimit(1)
                    Spacer()
                    Button {
                        document.delete(annotation.id)
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("Delete \(annotation.layerName)")
                }
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background(isSelected ? Theme.control : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture {
                    document.tool = .select
                    document.selectedId = annotation.id
                }
            }
        }
        .padding(16)
    }

    // MARK: Bottom bar

    private var zoomPercent: Int {
        let backing = NSScreen.main?.backingScaleFactor ?? 2
        return Int((document.zoom * backing * 100).rounded())
    }

    /// Screenshots of several displays: pick one display or all of them side by side.
    @ViewBuilder
    private var screenPicker: some View {
        if let screens = document.capture.screens, screens.count > 1 {
            HStack(spacing: 8) {
                Image(systemName: "display.2")
                    .foregroundStyle(Theme.textSecondary)
                Picker(selection: Binding(get: { document.capture.selectedScreen ?? screens[0].id }, set: { id in onSelectScreen(id) })) {
                    ForEach(screens) { screen in
                        Text(screen.name).tag(screen.id)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(switchingScreen)
                if switchingScreen {
                    ProgressView().controlSize(.small)
                }
            }
            .help("Which screen is in the screenshot. Each one keeps its own marks.")
            .padding(.leading, 8)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { setZoom(document.zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.plain)
                .accessibilityLabel("Zoom out")
            Text("\(zoomPercent)%").font(.system(size: 12, design: .monospaced)).frame(width: 48)
            Button { setZoom(document.zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.plain)
                .accessibilityLabel("Zoom in")
            Button("Fit") { document.fitRequest += 1 }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.link)
            Button("100%") {
                let backing = NSScreen.main?.backingScaleFactor ?? 2
                setZoom(1 / backing)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.link)

            Text(sizeLabel).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)

            screenPicker

            if let message = document.message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.success)
                    .transition(.opacity)
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        document.message = nil
                    }
            }

            Spacer()

            DragOutHandle(document: document)

            Picker("", selection: $document.exportFormat) {
                ForEach(ScreenshotDocument.ExportFormat.allCases) { format in
                    Text(exportLabel(format)).tag(format)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 210)
            .labelsHidden()
            .help("File type and quality for Save, Drag and the file in Copy, with the size it comes out at. \(document.exportFormat.detail)")

            Button("Save to folder") {
                if let url = document.saveToFolder() {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .buttonStyle(SecondaryButtonStyle())

            Button("Copy  ⌘C") { document.copyToPasteboard() }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut("c", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    /// "JPEG, medium · 240 KB"; the size appears once it is measured.
    private func exportLabel(_ format: ScreenshotDocument.ExportFormat) -> String {
        guard let size = document.exportSizeText(format) else { return format.rawValue }
        return "\(format.rawValue) · \(size)"
    }

    private var sizeLabel: String {
        let area = document.crop ?? CGRect(origin: .zero, size: document.imageSize)
        return "\(Int(area.width))×\(Int(area.height))"
    }

    private func setZoom(_ value: CGFloat) {
        document.zoom = max(0.05, min(8, value))
    }

    private func combine() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Pick screenshots to place to the right"
        panel.directoryURL = AppSettings.shared.outputFolder
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let image = ImageFiles.load(url) {
                    document.combine(with: image)
                }
            }
        }
    }
}

/// Drag this into Jira, Slack or Finder to drop the rendered image as a file.
private struct DragOutHandle: View {
    let document: ScreenshotDocument

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
        .help("Drag the edited image into another app")
        .onDrag {
            guard let url = document.renderToTemporaryFile() else { return NSItemProvider() }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
    }
}
