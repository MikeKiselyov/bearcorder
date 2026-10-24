import AppKit
import QAHelperCore
import SwiftUI
import UniformTypeIdentifiers

struct ScreenshotEditorView: View {
    let capture: Capture
    @State private var document: ScreenshotDocument?

    var body: some View {
        Group {
            if let document = document {
                ScreenshotEditorContent(document: document)
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
                document = ScreenshotDocument(capture: capture)
            }
        }
    }
}

private struct ScreenshotEditorContent: View {
    @Bindable var document: ScreenshotDocument

    static let editorTools: [AnnotationTool] = [.select, .arrow, .rectangle, .ellipse, .line, .highlighter, .pen, .text, .step, .blur, .magnifier, .crop]
    static let colors: [AnnotationColor] = [.coral, .yellow, .blue, .green, .purple, .white, .black]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(Theme.border)
            HStack(spacing: 0) {
                AnnotationCanvas(document: document)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) { cropHint }
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
            ForEach(Self.editorTools) { tool in
                ToolButton(systemImage: tool.symbol, help: "\(tool.title) (\(String(tool.keyboardShortcut ?? " ").uppercased()))", isSelected: document.tool == tool) {
                    document.tool = tool
                }
            }
            ToolButton(systemImage: "rectangle.split.2x1", help: "Combine with another screenshot") {
                combine()
            }

            Rectangle().fill(Theme.borderStrong).frame(width: 1, height: 24).padding(.horizontal, 8)

            HStack(spacing: 6) {
                ForEach(Self.colors) { color in
                    Button {
                        document.color = color
                        document.applyStyleToSelection()
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Theme.text, lineWidth: document.color == color ? 2 : 0))
                            .overlay(Circle().stroke(Theme.borderStrong, lineWidth: color == .black ? 1 : 0))
                            .frame(width: 26, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.rawValue)
                }
            }

            Rectangle().fill(Theme.borderStrong).frame(width: 1, height: 24).padding(.horizontal, 8)

            HStack(spacing: 3) {
                ForEach(StrokeSize.allCases) { size in
                    Button {
                        document.stroke = size
                        document.applyStyleToSelection()
                    } label: {
                        RoundedRectangle(cornerRadius: min(2, size.width / 2))
                            .fill(Theme.text)
                            .frame(width: 14, height: min(size.width, 16))
                            .frame(width: 24, height: 28)
                            .background(document.stroke == size ? Color(hex: 0x45484F) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Line: \(size.rawValue). + and - step through sizes")
                    .accessibilityLabel("\(size.rawValue) stroke")
                }
            }
            .padding(3)
            .background(Theme.control)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            HStack(spacing: 2) {
                Button {
                    document.textPoints = TextSizes.stepped(from: document.textPoints, -1)
                    document.applySizeToSelection()
                } label: {
                    Text("A").font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Smaller text (- with Text or Step)")
                Text("\(Int(document.textPoints))")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 28)
                    .accessibilityLabel("Text size \(Int(document.textPoints))")
                Button {
                    document.textPoints = TextSizes.stepped(from: document.textPoints, 1)
                    document.applySizeToSelection()
                } label: {
                    Text("A").font(.system(size: 17, weight: .semibold)).frame(width: 24, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Bigger text (+ with Text or Step)")
            }
            .padding(.horizontal, 3)
            .background(Theme.control)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            Spacer()

            ToolButton(systemImage: "arrow.uturn.backward", help: "Undo (⌘Z)") { document.undo() }
                .disabled(!document.canUndo)
            ToolButton(systemImage: "arrow.uturn.forward", help: "Redo (⇧⌘Z)") { document.redo() }
                .disabled(!document.canRedo)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    @ViewBuilder
    private var cropHint: some View {
        if document.tool == .crop {
            HStack(spacing: 10) {
                Text("Drag to crop · Enter to apply · Esc to cancel").font(.system(size: 12))
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
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 84)
            .labelsHidden()

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
