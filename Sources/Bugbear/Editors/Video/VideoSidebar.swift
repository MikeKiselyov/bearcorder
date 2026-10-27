import BugbearCore
import SwiftUI

/// Right panel: overlay switches, the selected item, environment and export settings.
struct VideoSidebar: View {
    @Bindable var model: VideoEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                overlaysPanel
                Divider().overlay(Theme.border)
                selectionPanel
                Divider().overlay(Theme.border)
                environmentPanel
                    .onAppear { model.refreshEnvironmentFields(includingYourFields: false) }
                    .onChange(of: EnvironmentCollector.fieldSettings) { model.refreshEnvironmentFields(includingYourFields: true) }
                Divider().overlay(Theme.border)
                exportPanel
            }
            // The panel's width holds whatever is inside: a wide button pushed it out of the window.
            .frame(width: 270)
        }
        .frame(width: 270)
        .background(Theme.sidebar)
    }

    private func binding(_ keyPath: WritableKeyPath<VideoProject, Bool>) -> Binding<Bool> {
        return Binding(get: {
            model.project[keyPath: keyPath]
        }, set: { value in
            model.checkpoint()
            model.project[keyPath: keyPath] = value
            model.projectChanged()
        })
    }

    private var overlaysPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Overlays")
            SettingToggle(title: "Highlight clicks", isOn: binding(\.showClicks))
            SettingToggle(title: "Show keystrokes", isOn: binding(\.showKeys))
            SettingToggle(title: "Show steps", isOn: Binding(get: {
                model.project.isShowingSteps
            }, set: { value in
                model.checkpoint()
                model.project.showSteps = value
                model.projectChanged()
            }))
            .tip("Caption each step at the bottom: clicks, typing and pages opened, like in the bug report")
            SettingToggle(title: "Environment badge", isOn: binding(\.showBadge))
            if model.project.showBadge {
                Picker("Corner", selection: Binding(get: { model.project.badgeCorner }, set: { value in
                    model.project.badgeCorner = value
                    model.projectChanged()
                })) {
                    ForEach(BadgeCorner.allCases) { corner in
                        Text(corner.title).tag(corner)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 12))
            }
            if model.capture.events.isEmpty {
                Text("No clicks or keys were recorded for this clip.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var selectionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let overlay = model.selectedOverlay {
                SectionLabel("Selected · \(overlay.kind.title)")
                if overlay.kind == .text {
                    TextField("Text", text: Binding(get: {
                        model.selectedOverlay?.text ?? ""
                    }, set: { value in
                        var updated = overlay
                        updated.text = value
                        model.updateOverlay(updated)
                    }))
                    .textFieldStyle(.roundedBorder)
                    Picker("Background", selection: Binding(get: {
                        model.selectedOverlay?.clearBackground ?? false
                    }, set: { clear in
                        model.setSelectedTextClear(clear)
                    })) {
                        Text("Label").tag(false)
                        Text("Transparent").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .font(.system(size: 12))
                }
                if overlay.kind != .blur {
                    ColorPalette(selection: overlay.color, swatchSize: 16) { color in
                        var updated = model.selectedOverlay ?? overlay
                        updated.color = color
                        model.checkpoint()
                        model.updateOverlay(updated)
                    }
                }
                if overlay.kind != .blur {
                    HStack(spacing: 8) {
                        Text("Size").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Button {
                            model.changeSelectedOverlaySize(by: -1)
                        } label: {
                            Image(systemName: "minus").frame(width: 24, height: 22).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Smaller mark")
                        .tip("Smaller (-)")
                        Text("\(Int(overlay.effectiveScale * 100))%")
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 46)
                        Button {
                            model.changeSelectedOverlaySize(by: 1)
                        } label: {
                            Image(systemName: "plus").frame(width: 24, height: 22).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Bigger mark")
                        .tip("Bigger (+)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.control)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                Text("\(TimeFormat.clock(overlay.span.start, tenths: true)) – \(TimeFormat.clock(overlay.span.end, tenths: true))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                deleteButton
            } else if let item = model.selection {
                SectionLabel(selectionTitle(item))
                deleteButton
            } else {
                SectionLabel("How to edit")
                VStack(alignment: .leading, spacing: 6) {
                    hint("Drag on the ruler to select a range")
                    hint("Cut, Slow-mo and marks use that range")
                    hint("Pick Text, Arrow, Box or Blur, then drag on the video")
                    hint("Drag bars to move, edges to resize")
                    hint("Space plays, I / O trim, Delete removes")
                    hint("+ and - resize the selected text, arrow or box")
                }
            }
        }
        .padding(16)
    }

    private func hint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("·").foregroundStyle(Theme.textSecondary)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func selectionTitle(_ item: TimelineItem) -> String {
        switch item {
        case .overlay: return "Selected"
        case .cut: return "Selected · Cut"
        case .speed: return "Selected · Slow motion"
        case .freeze: return "Selected · Freeze frame"
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            model.deleteSelection()
        } label: {
            Label("Remove", systemImage: "trash").font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accentSoft)
    }

    private var environmentPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Environment")
                Spacer()
                Button("Edit") {
                    WindowManager.shared.openSettings(page: .reports)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.link)
                .tip("Choose the fields, their names and your own fields in Settings → Bug reports")
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.capture.environment.markdown(), forType: .string)
                    model.message = "Environment copied"
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.link)
            }
            CopyReportButton(help: "Steps from your clicks and keys, environment and the saved file", stepCount: model.reportStepCount) { format in
                model.copyBugReport(format: format)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 14) {
                if CaptureStore.shared.hasSystemLog(model.capture) {
                    Button("System log") { SystemActions.open(model.capture.systemLogURL) }
                }
                if FileManager.default.fileExists(atPath: model.capture.crashReportURL.path) {
                    Button("Crash report") { SystemActions.open(model.capture.crashReportURL) }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.link)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(Array(model.capture.environment.rows().enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.label).foregroundStyle(Theme.textSecondary)
                        Text(row.value).lineLimit(2).textSelection(.enabled)
                    }
                    .font(.system(size: 12))
                }
            }
        }
        .padding(16)
    }

    private var exportPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Export")
            PillPicker(options: VideoExportFormat.allCases, selection: Binding(get: { model.project.format }, set: { value in
                model.project.format = value
                model.projectChanged()
            })) { format in format.rawValue }
            if model.project.format == .mp4 {
                row("Quality") {
                    Picker("", selection: Binding(get: { model.project.quality }, set: { value in
                        model.project.quality = value
                        model.projectChanged()
                    })) {
                        ForEach(VideoQuality.allCases) { quality in
                            Text(model.qualityLabel(quality)).tag(quality)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 170)
                    .accessibilityLabel("Quality")
                    .tip("Picture size of the MP4 and about how big the file comes out. Lower quality makes a smaller file")
                }
                row("Size limit") {
                    Picker("", selection: Binding(get: { model.project.sizeLimitMB ?? 0 }, set: { value in
                        if value == 0 {
                            model.project.sizeLimitMB = nil
                        } else {
                            model.project.sizeLimitMB = value
                        }
                        model.projectChanged()
                    })) {
                        Text("Off").tag(0)
                        Text("10 MB").tag(10)
                        Text("25 MB").tag(25)
                        Text("50 MB").tag(50)
                        Text("100 MB").tag(100)
                    }
                    .labelsHidden()
                    .accessibilityLabel("Size limit")
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }
            } else {
                row("Frame rate") {
                    Picker("", selection: Binding(get: { model.project.gifFramesPerSecond }, set: { value in
                        model.project.gifFramesPerSecond = value
                        model.projectChanged()
                    })) {
                        Text("8 fps").tag(8)
                        Text("12 fps").tag(12)
                        Text("15 fps").tag(15)
                    }
                    .labelsHidden()
                    .accessibilityLabel("GIF frame rate")
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }
            }
            row("Length") {
                Text("\(TimeFormat.clock(model.outputDuration)) of \(TimeFormat.clock(model.duration))")
            }
            row("Est. size") {
                Text(model.estimatedSizeText)
            }
            if model.project.format == .gif && model.outputDuration > 20 {
                Text("GIFs longer than ~20 s get large. Trim or use MP4.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            content()
        }
        .font(.system(size: 13))
    }
}
