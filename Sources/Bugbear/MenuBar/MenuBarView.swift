import AppKit
import BugbearCore
import SwiftUI

enum MenuTab: String, CaseIterable, Identifiable {
    case capture = "Capture"
    case record = "Record"
    case tools = "Tools"
    case recent = "Recent"
    case space = "Space"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .capture: return "camera.viewfinder"
        case .record: return "record.circle"
        case .tools: return "wrench.and.screwdriver"
        case .recent: return "clock"
        case .space: return "internaldrive"
        }
    }

    /// The color of the tab's icon tile.
    var tint: TileTint {
        switch self {
        case .capture: return .coral
        case .record: return .pink
        case .tools: return .purple
        case .recent: return .blue
        case .space: return .green
        }
    }

    var help: String {
        switch self {
        case .capture: return "Save clips from the buffer, take screenshots and see the environment info"
        case .record: return "Record the screen and check layouts: resize, measure, pick colors, overlay a design"
        case .tools: return "Open the dev toolbox and the world clock"
        case .recent: return "Your latest screenshots and clips, click one to open it in the editor"
        case .space: return "Find and clean up what takes disk space"
        }
    }
}

struct MenuBarView: View {
    @Environment(AppState.self) private var app
    @AppStorage("menuTab") private var tab: MenuTab = .capture

    var body: some View {
        VStack(spacing: 0) {
            header
            bufferSection
            tabBar
            // One fixed height for every tab: the menu bar panel does not resize when the tab
            // changes, so taller content was cut off at the bottom.
            ScrollView {
                tabContent
            }
            .frame(height: MenuBarView.contentHeight)
            Divider().overlay(Theme.border)
            footer
        }
        .frame(width: 360)
        .auroraBackground()
        .foregroundStyle(Theme.text)
        .task {
            await app.refreshEnvironmentPreview()
            app.refreshStatus(force: true)
        }
        .onChange(of: app.recording != nil) { _, isRecording in
            if isRecording { tab = .record }
        }
    }

    /// Fits the tallest tab (Capture) without scrolling.
    static let contentHeight: CGFloat = 450

    private var tabContent: some View {
            Group {
                switch tab {
                case .capture:
                    VStack(spacing: 0) {
                        saveSection
                        captureSection
                        environmentSection
                    }
                case .record:
                    recordSection
                case .tools:
                    VStack(spacing: 0) {
                        toolboxSection
                        Divider().overlay(Theme.border)
                        WorldClockSection()
                    }
                case .recent:
                    recentSection
                case .space:
                    SpaceTabSection()
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(MenuTab.allCases) { item in
                let isSelected = item == tab
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 4) {
                        IconTile(systemImage: item.symbol, tint: item.tint, size: 28)
                            .saturation(isSelected ? 1 : 0.55)
                        Text(item.rawValue).font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    }
                    .foregroundStyle(isSelected ? Theme.text : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(isSelected ? Theme.controlSelected : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tip(item.help)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: Header and buffer

    private var header: some View {
        HStack(spacing: 10) {
            // The same glyph as in the menu bar, so the panel is easy to recognise.
            Image(nsImage: Logo.menuBarImage(recording: false))
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 27)
                .foregroundStyle(Theme.text)
            VStack(alignment: .leading, spacing: 1) {
                Text(AppInfo.name).font(.system(size: 14, weight: .bold))
                // The update badge needs the room; the tagline comes back once updated.
                if !Updater.shared.hasUpdate {
                    Text("Catch the bug that already happened")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            UpdateBadge()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusText: String {
        switch app.bufferState {
        case .running: return "Buffer recording"
        case .starting: return "Starting buffer…"
        case .paused, .off: return "Buffer paused"
        case .needsPermission: return "Screen Recording permission needed"
        case .failed(let message): return "Buffer error: \(message)"
        }
    }

    private var statusColor: Color {
        switch app.bufferState {
        case .running: return Theme.accent
        case .starting: return Theme.warning
        case .needsPermission, .failed: return Theme.warning
        default: return Theme.textTertiary
        }
    }

    private var bufferSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.8), radius: 4)
                Text(statusText)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Spacer()
                Text(bufferDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            if app.bufferState == .needsPermission {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Allow \(AppInfo.name) in System Settings › Privacy & Security › Screen & System Audio Recording, then reopen the app.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Grant access") { app.requestScreenRecordingAccess() }
                            .buttonStyle(AccentButtonStyle())
                            .tip("Ask macOS for Screen Recording access so the buffer can run")
                        Button("Relaunch") { relaunch() }
                            .buttonStyle(SecondaryButtonStyle())
                            .tip("Restart \(AppInfo.name) so a newly granted permission takes effect")
                    }
                }
            } else if case .failed(let message) = app.bufferState {
                Button("Report this problem") {
                    Feedback.openErrorReport(title: "Buffer error", message: message)
                }
                .buttonStyle(SecondaryButtonStyle())
                .tip("Open a GitHub issue about this error with the version, macOS and logs filled in")
            } else {
                activityBars
                HStack {
                    Text("−" + TimeFormat.clock(app.settings.bufferSeconds))
                    Spacer()
                    Text("−" + TimeFormat.clock(app.settings.bufferSeconds / 2))
                    Spacer()
                    Text("now").foregroundStyle(Theme.accentSoft)
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .glassCard()
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    private var bufferDetail: String {
        var parts: [String] = ["Last \(TimeFormat.clock(app.settings.bufferSeconds))", app.settings.qualityLabel]
        if app.settings.captureAllDisplays && app.displayCount > 1 {
            parts.append("\(app.displayCount) displays")
        }
        return parts.joined(separator: " · ")
    }

    private var activityBars: some View {
        let count = app.activity.count
        let filledFraction = app.settings.bufferSeconds > 0 ? app.coveredSeconds / app.settings.bufferSeconds : 0
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<count, id: \.self) { index in
                let isCovered = Double(count - index) / Double(count) <= filledFraction + 0.001
                let level = app.activity[index]
                let isRecent = index >= count - 4
                RoundedRectangle(cornerRadius: 3)
                    .fill(barStyle(isCovered: isCovered, isRecent: isRecent))
                    .frame(height: max(4, 34 * (isCovered ? max(0.18, level) : 0.15)))
                    .shadow(color: Theme.accent.opacity(isCovered && isRecent ? 0.5 : 0), radius: 5)
            }
        }
        .frame(height: 34, alignment: .bottom)
        .accessibilityLabel("Buffer holds \(Int(app.coveredSeconds)) seconds")
    }

    /// The last seconds glow coral, the rest of what the buffer holds is glass, the empty part faint.
    private func barStyle(isCovered: Bool, isRecent: Bool) -> AnyShapeStyle {
        if isCovered && isRecent {
            return AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFFB199), Theme.accent], startPoint: .top, endPoint: .bottom))
        }
        if isCovered {
            return AnyShapeStyle(Color.white.opacity(0.16))
        }
        return AnyShapeStyle(Color.white.opacity(0.05))
    }

    // MARK: Save from buffer

    private var saveOptions: [(label: String, seconds: Double, shortcut: String)] {
        let full = app.settings.bufferSeconds
        var options: [(label: String, seconds: Double, shortcut: String)] = [
            (label: "30 s", seconds: 30, shortcut: HotKeySettings.shared.text(for: .saveShort)),
            (label: "1 min", seconds: 60, shortcut: HotKeySettings.shared.text(for: .saveMinute)),
        ]
        if full > 60 {
            options.append((label: TimeFormat.clock(full).replacingOccurrences(of: ":00", with: "") + " min", seconds: full, shortcut: HotKeySettings.shared.text(for: .saveBuffer)))
        }
        return options
    }

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Save from buffer")
                Spacer()
                if app.isSaving {
                    ProgressView().controlSize(.small)
                    Text("Saving…").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(spacing: 8) {
                ForEach(Array(saveOptions.enumerated()), id: \.offset) { index, option in
                    let isPrimary = index == 1
                    let available = app.bufferState == .running && app.coveredSeconds >= min(option.seconds, 3)
                    Button {
                        Task { await app.saveFromBuffer(seconds: option.seconds) }
                    } label: {
                        VStack(spacing: 2) {
                            Text(option.label).font(.system(size: 15, weight: isPrimary ? .bold : .semibold))
                            Text(option.shortcut)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isPrimary ? Color(hex: 0x3D1A10) : Theme.textSecondary)
                        }
                        .foregroundStyle(isPrimary ? Theme.accentText : Theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(isPrimary ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.panel))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isPrimary ? Color.clear : Theme.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: Theme.accent.opacity(isPrimary && available ? 0.4 : 0), radius: 12, y: 5)
                        .opacity(available ? 1 : 0.45)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tip("Save the last \(option.label) of the screen from the buffer as a clip (\(option.shortcut))")
                    .disabled(!available || app.isSaving)
                }
            }
        }
        .padding(12)
    }

    // MARK: Capture

    private var captureSection: some View {
        VStack(spacing: 0) {
            MenuRow(systemImage: "viewfinder", tint: .coral, title: "Screenshot area", shortcut: HotKeySettings.shared.text(for: .screenshotArea)) {
                Task { await app.takeScreenshot(.area) }
            }
            .tip("Select an area of the screen and capture it (\(HotKeySettings.shared.text(for: .screenshotArea)))")
            MenuRow(systemImage: "macwindow", tint: .blue, title: "Screenshot window", shortcut: HotKeySettings.shared.text(for: .screenshotWindow)) {
                Task { await app.takeScreenshot(.window) }
            }
            .tip("Click a window to capture just that window (\(HotKeySettings.shared.text(for: .screenshotWindow)))")
            if app.displayCount > 1 {
                MenuRow(systemImage: "rectangle.split.2x1", tint: .green, title: "Screenshot all displays", shortcut: "") {
                    Task { await app.takeScreenshot(.allDisplays) }
                }
                .tip("Capture every connected display in one image")
            } else {
                MenuRow(systemImage: "display", tint: .green, title: "Screenshot full screen", shortcut: "") {
                    Task { await app.takeScreenshot(.fullScreen) }
                }
                .tip("Capture the whole screen")
            }
            MenuRow(systemImage: "arrow.down.to.line.compact", tint: .teal, title: "Scrolling screenshot", shortcut: HotKeySettings.shared.text(for: .scrollingScreenshot)) {
                Task { await app.takeScrollingScreenshot() }
            }
            .tip("Capture a long page by scrolling it into one tall image (\(HotKeySettings.shared.text(for: .scrollingScreenshot)))")
            MenuRow(systemImage: "text.viewfinder", tint: .purple, title: "Copy text from screen", shortcut: HotKeySettings.shared.text(for: .copyText)) {
                Task { await app.copyTextFromScreen() }
            }
            .tip("Select an area and copy the text in it to the clipboard (\(HotKeySettings.shared.text(for: .copyText)))")
        }
        .padding(4)
        .glassCard()
        .padding(.horizontal, 12)
    }

    // MARK: Record

    private var recordSection: some View {
        @Bindable var state = app
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Record")
                Spacer()
                Text("\(HotKeySettings.shared.text(for: .recordToggle)) start/stop · \(HotKeySettings.shared.text(for: .recordPause)) pause")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            if let session = app.recording {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    HStack {
                        Circle().fill(session.isPaused ? Theme.warning : Theme.accent).frame(width: 9, height: 9)
                        Text(session.isPaused ? "Paused" : "Recording")
                            .font(.system(size: 13, weight: .semibold))
                        Text(TimeFormat.clock(session.elapsed()))
                            .font(.system(size: 13, design: .monospaced))
                        Spacer()
                        Button(session.isPaused ? "Resume" : "Pause") { session.togglePause() }
                            .buttonStyle(SecondaryButtonStyle())
                            .tip("Pause or resume the recording (\(HotKeySettings.shared.text(for: .recordPause)))")
                        Button("Stop") { Task { await app.stopRecording() } }
                            .buttonStyle(AccentButtonStyle())
                            .tip("Stop and save the recording (\(HotKeySettings.shared.text(for: .recordToggle)))")
                    }
                }
            } else {
                PillPicker(options: RecordingTarget.allCases, selection: $state.recordingTarget) { target in
                    switch target {
                    case .screens:
                        return app.settings.captureAllDisplays && app.displayCount > 1 ? "All displays" : "Full screen"
                    case .area:
                        return "Area…"
                    }
                }
                .tip("Choose what to record: the full screen or an area you select")
                HStack(spacing: 6) {
                    ToggleChip(systemImage: "mic.fill", title: "Mic", isOn: app.settings.recordMicrophone) {
                        app.settings.recordMicrophone.toggle()
                        Task { await app.restartBufferIfRunning() }
                    }
                    .tip("Record your microphone together with the screen")
                    ToggleChip(systemImage: "speaker.wave.2.fill", title: "System audio", isOn: app.settings.recordSystemAudio) {
                        app.settings.recordSystemAudio.toggle()
                        Task { await app.restartBufferIfRunning() }
                    }
                    .tip("Record the sound your Mac plays together with the screen")
                    ToggleChip(systemImage: "web.camera.fill", title: "Camera", isOn: app.cameraOn) {
                        Task { await app.setCamera(!app.cameraOn) }
                    }
                    .tip("Show your camera in a bubble on screen so it gets into the recording")
                }
                HStack(spacing: 8) {
                    Button {
                        Task { await app.startRecording(target: app.recordingTarget) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "record.circle")
                            Text("Start recording")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AccentButtonStyle())
                    .tip("Start recording the screen to a video (\(HotKeySettings.shared.text(for: .recordToggle)))")
                    Button {
                        app.closeMenuPanel()
                        app.toggleDrawing()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil.and.scribble")
                            Text("Draw")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .tip("Draw arrows and boxes on screen (\(HotKeySettings.shared.text(for: .draw)))")
                }
            }
            screenChecks
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Resize the window under test, measure, pick colors, overlay a design.
    private var screenChecks: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel("Check the screen")
                .padding(.horizontal, 10)
                .padding(.top, 8)
            Menu {
                Section("Desktop") {
                    ForEach(WindowResizer.desktopPresets) { preset in
                        Button(preset.title) { app.resizeFrontWindow(to: preset) }
                    }
                }
                Section("Mobile and tablet width") {
                    ForEach(WindowResizer.mobilePresets) { preset in
                        Button(preset.title) { app.resizeFrontWindow(to: preset) }
                    }
                }
            } label: {
                checkRowLabel("macwindow", "Resize the window you test", detail: app.lastExternalAppName)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Resize the window you test")
            .tip("Resize the last app window to a desktop or mobile preset to test responsive layouts")
            Button { app.startRuler() } label: {
                checkRowLabel("ruler", "Measure on screen", detail: "")
            }
            .buttonStyle(.plain)
            .tip("Measure distances in pixels between points on the screen")
            Button { app.pickColor() } label: {
                checkRowLabel("eyedropper", "Pick a color", detail: "copies hex")
            }
            .buttonStyle(.plain)
            .tip("Pick any color on the screen and copy its hex value")
            Menu {
                Button("From a file…") { app.openDesignOverlay(fromClipboard: false) }
                Button("From the clipboard") { app.openDesignOverlay(fromClipboard: true) }
            } label: {
                checkRowLabel("square.on.square.dashed", "Overlay a design", detail: "")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Overlay a design")
            .tip("Lay a design mockup over the screen to compare it with the real UI")
        }
        .padding(.vertical, 4)
        .glassCard()
        .padding(.top, 4)
    }

    private func checkRowLabel(_ symbol: String, _ title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            IconTile(systemImage: symbol, tint: checkTint(symbol), size: 24)
            Text(title).font(.system(size: 13))
            Spacer()
            Text(detail).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .contentShape(Rectangle())
    }

    private func checkTint(_ symbol: String) -> TileTint {
        switch symbol {
        case "macwindow": return .blue
        case "ruler": return .yellow
        case "eyedropper": return .pink
        default: return .teal
        }
    }

    // MARK: Toolbox

    private var toolboxSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Dev toolbox")
                Spacer()
                Text(HotKeySettings.shared.text(for: .toolbox)).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            FlowChips(items: [
                ("{ } JSON", ToolKind.json), ("XML", .xml), ("YAML", .yaml), ("HTML", .html), ("SQL", .sql),
                ("GraphQL", .graphql), ("JWT", .jwt), ("Base64", .base64), ("URL", .url), ("&; Entities", .htmlEntities),
                ("Time", .time), ("Time zones", .timeZones), ("⇄ Convert", .dataConvert), ("0x · Color · Case", .quick), ("UUID · Hash", .generate), ("Test data", .testData), ("Regex", .regex), ("QR", .qr),
            ]) { tool in
                app.openToolbox(tool: tool)
            } trailing: {
                Button("All tools") { app.openToolbox(tool: nil) }
                    .buttonStyle(.plain)
                    .tip("Open the dev toolbox window with every tool (\(HotKeySettings.shared.text(for: .toolbox)))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.link)
                    .frame(height: 28)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Environment

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Environment · auto")
                Spacer()
                Button("Edit") { editReportFields() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.link)
                    .tip("Choose the fields, their names and your own fields in Settings → Bug reports")
            }
            if let environment = app.environmentPreview, environment.rows().isEmpty {
                // Every field turned off or empty: say so, instead of an empty card.
                HStack(spacing: 8) {
                    Text("No fields to show")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Button("Choose fields") { editReportFields() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.link)
                }
            } else if let environment = app.environmentPreview {
                FlowLayout(spacing: 5) {
                    ForEach(Array(environment.rows().prefix(5).enumerated()), id: \.offset) { _, row in
                        Text(row.label == "macOS" ? "macOS \(row.value)" : row.value)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 300)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(Theme.control)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .accessibilityLabel("\(row.label): \(row.value)")
                            .tip(row.label)
                    }
                }
            } else {
                Text("Collecting…").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .padding(12)
    }

    private func editReportFields() {
        app.closeMenuPanel()
        WindowManager.shared.openSettings(page: .reports)
    }

    // MARK: Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Recent")
                Spacer()
                Button("All captures") {
                    app.closeMenuPanel()
                    WindowManager.shared.openHistory()
                }
                .buttonStyle(.plain)
                .tip("Open the history window with all your screenshots and clips")
                .font(.system(size: 12))
                .foregroundStyle(Theme.link)
            }
            if app.store.captures.isEmpty {
                Text("Nothing captured yet. Press \(HotKeySettings.shared.text(for: .screenshotArea)) for a screenshot or \(HotKeySettings.shared.text(for: .saveMinute)) to save the last minute.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                    ForEach(Array(app.store.captures.prefix(9))) { capture in
                        Button {
                            app.closeMenuPanel()
                            WindowManager.shared.openEditor(for: capture)
                        } label: {
                            CaptureThumbnail(capture: capture, height: 58)
                        }
                        .buttonStyle(.plain)
                        .tip("Open this capture in the editor")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 4) {
            Button {
                Task { await app.toggleBuffer() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: app.bufferState == .running ? "pause.fill" : "play.fill")
                    Text(app.bufferState == .running ? "Pause buffer" : "Start buffer")
                }
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tip("The buffer keeps the last minutes of the screen so you can save a bug after it happened")
            Spacer()
            ToolButton(systemImage: "exclamationmark.bubble", help: "Report a problem with \(AppInfo.name) or suggest a feature on GitHub") {
                WindowManager.shared.openFeedback(kind: .problem)
            }
            ToolButton(systemImage: "gearshape", help: "Open settings: buffer, shortcuts, storage and more") {
                app.closeMenuPanel()
                WindowManager.shared.openSettings()
            }
            ToolButton(systemImage: "power", help: "Quit \(AppInfo.name)") {
                NSApp.terminate(nil)
            }
        }
        .padding(8)
        .background(Theme.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func relaunch() {
        Relaunch.now()
    }
}

struct MenuRow: View {
    let systemImage: String
    var tint: TileTint = .gray
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                IconTile(systemImage: systemImage, tint: tint, size: 24)
                Text(title).font(.system(size: 13))
                Spacer()
                Text(shortcut).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(hovering ? Theme.controlSelected : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in hovering = inside }
    }
}

struct ToggleChip: View {
    let systemImage: String
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 11))
                Text(title).font(.system(size: 12))
            }
            .foregroundStyle(isOn ? Theme.accentText : Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(isOn ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.control))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isOn ? Color.clear : Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// Wrapping row of small tool chips.
struct FlowChips<Trailing: View>: View {
    let items: [(String, ToolKind)]
    let action: (ToolKind) -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.0) { item in
                Button {
                    action(item.1)
                } label: {
                    Text(item.0)
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Theme.control)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tip("Open \(item.0) in the dev toolbox")
            }
            trailing()
        }
    }
}

/// Minimal flow layout: places children left to right and wraps.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct CaptureThumbnail: View {
    @Environment(AppState.self) private var app
    let capture: Capture
    var height: CGFloat = 58

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                if let image = app.store.thumbnail(for: capture) {
                    // The cell sets the size and the picture fills it: an image sized by itself
                    // made wide captures (two displays) push the grid past the panel's edge.
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .overlay {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        .clipped()
                } else {
                    Rectangle().fill(Color(hex: 0x2E3136)).frame(height: height)
                }
                if capture.kind == .video {
                    Text(TimeFormat.clock(capture.duration))
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(hex: 0x111214))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(relative(capture.createdAt))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func relative(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) h ago" }
        return "\(Int(seconds / 86400)) d ago"
    }
}

/// Compact world clock in the Tools tab: saved zones next to your time.
struct WorldClockSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        TimelineView(.everyMinute) { context in
            let reference = TimeZone.current
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel("World clock")
                    Spacer()
                    Button("Compare…") { app.openToolbox(tool: .timeZones) }
                        .buttonStyle(.plain)
                        .tip("Open the time zones tool to compare times across cities")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.link)
                }
                HStack {
                    Text("You · \(WorldClock.city(of: reference.identifier))").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(TimeConverter.format(context.date, pattern: "HH:mm", timeZone: reference))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
                ForEach(app.settings.timeZones.prefix(5), id: \.self) { identifier in
                    if let info = WorldClock.compare(identifier, at: context.date, reference: reference) {
                        HStack(spacing: 8) {
                            Text(info.city).font(.system(size: 12)).lineLimit(1)
                            Text(info.differenceText)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(info.differenceSeconds == 0 ? Theme.textSecondary : (info.differenceSeconds > 0 ? Theme.warning : Theme.link))
                            Spacer()
                            if info.dayPart != .work {
                                Image(systemName: info.dayPart == .night ? "moon.fill" : "sun.haze")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textSecondary)
                                    .tip(info.dayPart.title)
                            }
                            Text(info.time + (info.dayHint.isEmpty ? "" : " ·"))
                                .font(.system(size: 13, design: .monospaced))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
