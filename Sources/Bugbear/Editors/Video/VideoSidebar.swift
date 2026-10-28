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
            SectionLabel(L("video.overlays.title"))
            SettingToggle(title: L("video.overlays.clicks"), isOn: binding(\.showClicks))
            SettingToggle(title: L("video.overlays.keys"), isOn: binding(\.showKeys))
            SettingToggle(title: L("video.overlays.steps"), isOn: Binding(get: {
                model.project.isShowingSteps
            }, set: { value in
                model.checkpoint()
                model.project.showSteps = value
                model.projectChanged()
            }))
            .tip(L("video.overlays.steps.tip"))
            SettingToggle(title: L("video.overlays.badge"), isOn: binding(\.showBadge))
            if model.project.showBadge {
                Picker(L("editors.badge.corner"), selection: Binding(get: { model.project.badgeCorner }, set: { value in
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
                Text(L("video.overlays.noEvents"))
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
                SectionLabel(L("editors.selected.title", overlay.kind.title))
                if overlay.kind == .text {
                    TextField(L("editors.selected.text"), text: Binding(get: {
                        model.selectedOverlay?.text ?? ""
                    }, set: { value in
                        var updated = overlay
                        updated.text = value
                        model.updateOverlay(updated)
                    }))
                    .textFieldStyle(.roundedBorder)
                    Picker(L("video.selected.background"), selection: Binding(get: {
                        model.selectedOverlay?.clearBackground ?? false
                    }, set: { clear in
                        model.setSelectedTextClear(clear)
                    })) {
                        Text(L("video.selected.background.label")).tag(false)
                        Text(L("video.selected.background.transparent")).tag(true)
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
                        Text(L("video.selected.size")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Button {
                            model.changeSelectedOverlaySize(by: -1)
                        } label: {
                            Image(systemName: "minus").frame(width: 24, height: 22).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("video.selected.smaller"))
                        .tip(L("video.selected.smaller.tip"))
                        Text("\(Int(overlay.effectiveScale * 100))%")
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 46)
                        Button {
                            model.changeSelectedOverlaySize(by: 1)
                        } label: {
                            Image(systemName: "plus").frame(width: 24, height: 22).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("video.selected.bigger"))
                        .tip(L("video.selected.bigger.tip"))
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
                SectionLabel(L("video.help.title"))
                VStack(alignment: .leading, spacing: 6) {
                    hint(L("video.help.selectRange"))
                    hint(L("video.help.useRange"))
                    hint(L("video.help.marks"))
                    hint(L("video.help.bars"))
                    hint(L("video.help.crop"))
                    hint(L("video.help.keys"))
                    hint(L("video.help.resize"))
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
        case .overlay: return L("video.selected.title")
        case .cut: return L("video.selected.cut")
        case .speed: return L("video.selected.slowMotion")
        case .freeze: return L("video.selected.freeze")
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            model.deleteSelection()
        } label: {
            Label(L("video.selected.remove"), systemImage: "trash").font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accentSoft)
    }

    private var environmentPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                Button(L("editors.environment.copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.capture.environment.markdown(), forType: .string)
                    model.message = L("editors.message.environmentCopied")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.link)
            }
            CopyReportButton(help: L("video.report.tip"), stepCount: model.reportStepCount) { format in
                model.copyBugReport(format: format)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 14) {
                if CaptureStore.shared.hasSystemLog(model.capture) {
                    Button(L("video.environment.systemLog")) { SystemActions.open(model.capture.systemLogURL) }
                }
                if FileManager.default.fileExists(atPath: model.capture.crashReportURL.path) {
                    Button(L("video.environment.crashReport")) { SystemActions.open(model.capture.crashReportURL) }
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
            SectionLabel(L("video.export.title"))
            PillPicker(options: VideoExportFormat.allCases, selection: Binding(get: { model.project.format }, set: { value in
                model.project.format = value
                model.projectChanged()
            })) { format in format.rawValue }
            if model.project.format == .mp4 {
                row(L("video.export.quality")) {
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
                    .accessibilityLabel(L("video.export.quality"))
                    .tip(L("video.export.quality.tip"))
                }
                row(L("video.export.sizeLimit")) {
                    Picker("", selection: Binding(get: { model.project.sizeLimitMB ?? 0 }, set: { value in
                        if value == 0 {
                            model.project.sizeLimitMB = nil
                        } else {
                            model.project.sizeLimitMB = value
                        }
                        model.projectChanged()
                    })) {
                        Text(L("video.export.sizeLimit.off")).tag(0)
                        Text(L("video.export.megabytes", 10)).tag(10)
                        Text(L("video.export.megabytes", 25)).tag(25)
                        Text(L("video.export.megabytes", 50)).tag(50)
                        Text(L("video.export.megabytes", 100)).tag(100)
                    }
                    .labelsHidden()
                    .accessibilityLabel(L("video.export.sizeLimit"))
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }
            } else {
                row(L("video.export.frameRate")) {
                    Picker("", selection: Binding(get: { model.project.gifFramesPerSecond }, set: { value in
                        model.project.gifFramesPerSecond = value
                        model.projectChanged()
                    })) {
                        Text(L("video.export.fps", 8)).tag(8)
                        Text(L("video.export.fps", 12)).tag(12)
                        Text(L("video.export.fps", 15)).tag(15)
                    }
                    .labelsHidden()
                    .accessibilityLabel(L("video.export.frameRate.gif"))
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }
            }
            row(L("video.export.length")) {
                Text(L("video.export.length.value", TimeFormat.clock(model.outputDuration), TimeFormat.clock(model.duration)))
            }
            row(L("video.export.estimatedSize")) {
                Text(model.estimatedSizeText)
            }
            if model.project.format == .gif && model.outputDuration > 20 {
                Text(L("video.export.gifTooLong"))
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
