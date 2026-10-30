import AppKit
import AppCore
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
                    Text(L("screenshot.openFailed")).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .auroraBackground()
        .onAppear {
            if document == nil {
                let opened = ScreenshotDocument(capture: capture)
                if AppState.shared.justCopiedScreenshot == capture.id {
                    opened?.message = L("screenshot.message.copiedOnCapture")
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
                AppState.shared.showError(L("editors.screen.switchFailed", error.localizedDescription))
            }
            switchingScreen = false
        }
    }
}

private struct ScreenshotEditorContent: View {
    @Bindable var document: ScreenshotDocument
    var switchingScreen: Bool
    var onSelectScreen: (String) -> Void

    static let editorTools = AnnotationTool.screenshotEditorTools

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                AnnotationCanvas(document: document)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) { cropHint }
                    .background(DeleteKeyMonitor(onDelete: {
                        if document.selectedId == nil {
                            return false
                        }
                        document.deleteSelected()
                        return true
                    }, onPaste: {
                        guard let image = CanvasView.image(from: NSPasteboard.general) else { return false }
                        document.insertImage(image)
                        return true
                    }))
                Rectangle().fill(Theme.border).frame(width: 1)
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
            ToolButton(systemImage: "arrow.uturn.backward", help: L("editors.undo.tip")) { document.undo() }
                .disabled(!document.canUndo)
            ToolButton(systemImage: "arrow.uturn.forward", help: L("editors.redo.tip")) { document.redo() }
                .disabled(!document.canRedo)

            Rectangle().fill(Theme.borderStrong).frame(width: 1, height: 22).padding(.horizontal, 6)

            ForEach(Self.editorTools) { tool in
                ToolButton(systemImage: tool.symbol, help: L("screenshot.tool.tip", tool.title, String(tool.keyboardShortcut ?? " ").uppercased(), tool.purpose), isSelected: document.tool == tool) {
                    document.tool = tool
                }
            }
            ToolButton(systemImage: "photo.badge.plus", help: L("screenshot.insertImage.tip")) {
                insertImage()
            }
            ToolButton(systemImage: "rectangle.split.2x1", help: L("screenshot.combine.tip")) {
                combine()
            }

            Rectangle().fill(Theme.borderStrong).frame(width: 1, height: 22).padding(.horizontal, 6)

            ColorPalette(selection: document.color, swatchSize: 18) { color in
                document.color = color
                document.applyStyleToSelection()
            }

            Rectangle().fill(Theme.borderStrong).frame(width: 1, height: 22).padding(.horizontal, 6)

            HStack(spacing: 6) {
                FillToggle(isFilled: document.isFilled, isEnabled: document.fillTarget != nil) { filled in
                    document.setFilled(filled)
                }
                SizeStepper(value: "\(document.sizeValue)", name: document.sizeIsText ? L("editors.size.text") : L("editors.size.line"), symbol: document.sizeIsText ? "textformat.size" : "lineweight") { direction in
                    document.changeSize(by: direction)
                }
            }

        }
        .padding(.horizontal, 6)
        .frame(height: 44)
        .glassCard(cornerRadius: 14)
        .shadow(color: Color.black.opacity(0.35), radius: 14, y: 6)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 52)
    }

    @ViewBuilder
    private var cropHint: some View {
        if document.tool == .crop {
            HStack(spacing: 10) {
                Text(L("screenshot.crop.hint")).font(.system(size: 12))
                if document.crop != nil {
                    Button(L("screenshot.crop.reset")) { document.setCrop(nil) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.link)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(hex: 0x1E1A24, alpha: 0.92))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 10)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                environmentPanel.frame(maxWidth: .infinity, alignment: .leading).glassCard()
                    .onAppear { document.refreshEnvironmentFields(includingYourFields: false) }
                    .onChange(of: EnvironmentCollector.fieldSettings) { document.refreshEnvironmentFields(includingYourFields: true) }
                if let selected = document.selected {
                    inspector(selected).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                }
                layersPanel.frame(maxWidth: .infinity, alignment: .leading).glassCard()
            }
            .padding(12)
        }
        .frame(width: 290)
        .background(Theme.sidebar)
    }

    private var environmentPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(L("editors.environment.title"))
                Spacer()
                Button(L("editors.environment.edit")) {
                    WindowManager.shared.openSettings(page: .reports)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.link)
                .tip(L("editors.environment.edit.tip"))
                Button(L("editors.environment.copy")) { document.copyEnvironment() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.link)
            }
            CopyReportButton(help: L("screenshot.report.tip"), stepCount: BugReportBuilder.stepCount(for: document.capture, timeMap: nil)) { format in
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
            SettingToggle(title: L("screenshot.badge.toggle"), isOn: Binding(get: { document.showBadge }, set: { value in
                document.showBadge = value
                document.saveProject()
            }))
            if document.showBadge {
                Picker(L("editors.badge.corner"), selection: Binding(get: { document.badgeCorner }, set: { value in
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
        .padding(14)
    }

    private func inspector(_ annotation: Annotation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(L("editors.selected.title", annotation.tool.title))
            if annotation.tool.hasLabel {
                TextField(L("editors.selected.text"), text: Binding(get: {
                    document.selected?.text ?? ""
                }, set: { value in
                    document.setText(value, for: annotation.id)
                }))
                .textFieldStyle(.roundedBorder)
            }
            if annotation.tool == .step {
                Stepper(L("screenshot.step.number", annotation.number), value: Binding(get: {
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
                Label(L("screenshot.selected.delete"), systemImage: "trash").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accentSoft)
        }
        .padding(14)
    }

    private var layersPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(L("screenshot.layers.title"))
            if document.annotations.isEmpty {
                Text(L("screenshot.layers.empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(document.annotations.reversed()) { annotation in
                let isSelected = annotation.id == document.selectedId
                HStack(spacing: 10) {
                    ToolIcon(name: annotation.tool.symbol, size: 11)
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
                    .accessibilityLabel(L("screenshot.layers.delete", annotation.layerName))
                }
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background(isSelected ? Theme.controlSelected : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .onTapGesture {
                    document.tool = .select
                    document.selectedId = annotation.id
                }
            }
        }
        .padding(14)
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
                            .accessibilityLabel(L("editors.screen.option", screen.name))
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
            .tip(L("screenshot.screen.tip"))
            .padding(.leading, 8)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { setZoom(document.zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.plain)
                .accessibilityLabel(L("screenshot.zoom.out"))
            Text("\(zoomPercent)%").font(.system(size: 12, design: .monospaced)).frame(width: 48)
            Button { setZoom(document.zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.plain)
                .accessibilityLabel(L("screenshot.zoom.in"))
            Button(L("screenshot.zoom.fit")) { document.fitRequest += 1 }
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
            .accessibilityLabel(L("screenshot.export.format"))
            .tip(L("screenshot.export.format.tip", document.exportFormat.detail))

            Button(L("editors.save")) {
                if let url = document.saveToFolder() {
                    SystemActions.reveal([url])
                }
            }
            .buttonStyle(SecondaryButtonStyle())

            Button(L("screenshot.copy")) { document.copyToPasteboard() }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut("c", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    /// "JPEG, medium · 240 KB"; the size appears once it is measured.
    private func exportLabel(_ format: ScreenshotDocument.ExportFormat) -> String {
        guard let size = document.exportSizeText(format) else { return format.title }
        return L("screenshot.export.option", format.title, size)
    }

    private var sizeLabel: String {
        let area = document.crop ?? CGRect(origin: .zero, size: document.imageSize)
        return "\(Int(area.width))×\(Int(area.height))"
    }

    private func setZoom(_ value: CGFloat) {
        document.zoom = max(0.05, min(8, value))
    }

    private func insertImage() {
        let urls = SystemActions.chooseImages(message: L("screenshot.insertImage.choose"), multiple: false, startingAt: AppSettings.shared.outputFolder)
        if let url = urls.first, let image = ImageFiles.load(url) {
            document.insertImage(image)
        }
    }

    private func combine() {
        let urls = SystemActions.chooseImages(message: L("screenshot.combine.choose"), multiple: true, startingAt: AppSettings.shared.outputFolder)
        for url in urls {
            if let image = ImageFiles.load(url) {
                document.combine(with: image)
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
            Text(L("editors.drag"))
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .contentShape(Rectangle())
        .tip(L("screenshot.drag.tip"))
        .onDrag {
            guard let url = document.renderToTemporaryFile() else { return NSItemProvider() }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
    }
}
