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
}

struct MenuBarView: View {
    @Environment(AppState.self) private var app
    @AppStorage("menuTab") private var tab: MenuTab = .capture

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            bufferSection
            tabBar
            Divider().overlay(Theme.border)
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
        .background(Theme.panel)
        .foregroundStyle(Theme.text)
        .task {
            await app.refreshEnvironmentPreview()
            app.refreshStatus()
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
                        Divider().overlay(Theme.border)
                        captureSection
                        Divider().overlay(Theme.border)
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
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol).font(.system(size: 13))
                        Text(item.rawValue).font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    }
                    .foregroundStyle(isSelected ? Theme.text : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(isSelected ? Theme.controlSelected : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
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
                Text("Bugbear").font(.system(size: 14, weight: .bold))
                Text("Catch the bug that already happened")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
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
                    Text("Allow Bugbear in System Settings › Privacy & Security › Screen & System Audio Recording, then reopen the app.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Grant access") { app.requestScreenRecordingAccess() }
                            .buttonStyle(AccentButtonStyle())
                        Button("Relaunch") { relaunch() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                RoundedRectangle(cornerRadius: 2)
                    .fill(isCovered ? (isRecent ? Theme.accent : Color(hex: 0x4A4D54)) : Color(hex: 0x2E3034))
                    .frame(height: max(4, 34 * (isCovered ? max(0.18, level) : 0.15)))
            }
        }
        .frame(height: 34, alignment: .bottom)
        .accessibilityLabel("Buffer holds \(Int(app.coveredSeconds)) seconds")
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
                        .frame(height: 54)
                        .background(isPrimary ? Theme.accent : Theme.control)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isPrimary ? Color.clear : Theme.borderStrong, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .opacity(available ? 1 : 0.45)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!available || app.isSaving)
                }
            }
        }
        .padding(12)
    }

    // MARK: Capture

    private var captureSection: some View {
        VStack(spacing: 0) {
            MenuRow(systemImage: "viewfinder", title: "Screenshot area", shortcut: HotKeySettings.shared.text(for: .screenshotArea)) {
                Task { await app.takeScreenshot(.area) }
            }
            MenuRow(systemImage: "macwindow", title: "Screenshot window", shortcut: HotKeySettings.shared.text(for: .screenshotWindow)) {
                Task { await app.takeScreenshot(.window) }
            }
            if app.displayCount > 1 {
                MenuRow(systemImage: "rectangle.split.2x1", title: "Screenshot all displays", shortcut: "") {
                    Task { await app.takeScreenshot(.allDisplays) }
                }
            } else {
                MenuRow(systemImage: "display", title: "Screenshot full screen", shortcut: "") {
                    Task { await app.takeScreenshot(.fullScreen) }
                }
            }
            MenuRow(systemImage: "arrow.down.to.line.compact", title: "Scrolling screenshot", shortcut: HotKeySettings.shared.text(for: .scrollingScreenshot)) {
                Task { await app.takeScrollingScreenshot() }
            }
            MenuRow(systemImage: "text.viewfinder", title: "Copy text from screen", shortcut: HotKeySettings.shared.text(for: .copyText)) {
                Task { await app.copyTextFromScreen() }
            }
        }
        .padding(8)
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
                        Button("Stop") { Task { await app.stopRecording() } }
                            .buttonStyle(AccentButtonStyle())
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
                HStack(spacing: 6) {
                    ToggleChip(systemImage: "mic.fill", title: "Mic", isOn: app.settings.recordMicrophone) {
                        app.settings.recordMicrophone.toggle()
                        Task { await app.restartBufferIfRunning() }
                    }
                    ToggleChip(systemImage: "speaker.wave.2.fill", title: "System audio", isOn: app.settings.recordSystemAudio) {
                        app.settings.recordSystemAudio.toggle()
                        Task { await app.restartBufferIfRunning() }
                    }
                    ToggleChip(systemImage: "web.camera.fill", title: "Camera", isOn: app.cameraOn) {
                        Task { await app.setCamera(!app.cameraOn) }
                    }
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
                    .help("Draw arrows and boxes on screen (\(HotKeySettings.shared.text(for: .draw)))")
                }
            }
            Divider().overlay(Theme.border).padding(.vertical, 2)
            screenChecks
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Resize the window under test, measure, pick colors, overlay a design.
    private var screenChecks: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel("Check the screen")
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
            Button { app.startRuler() } label: {
                checkRowLabel("ruler", "Measure on screen", detail: "")
            }
            .buttonStyle(.plain)
            Button { app.pickColor() } label: {
                checkRowLabel("eyedropper", "Pick a color", detail: "copies hex")
            }
            .buttonStyle(.plain)
            Menu {
                Button("From a file…") { app.openDesignOverlay(fromClipboard: false) }
                Button("From the clipboard") { app.openDesignOverlay(fromClipboard: true) }
            } label: {
                checkRowLabel("square.on.square.dashed", "Overlay a design", detail: "")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }

    private func checkRowLabel(_ symbol: String, _ title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(Theme.textSecondary)
            Text(title).font(.system(size: 13))
            Spacer()
            Text(detail).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
        .frame(height: 30)
        .contentShape(Rectangle())
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
            SectionLabel("Environment · auto")
            if let environment = app.environmentPreview {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    ForEach(Array(environment.rows().prefix(5).enumerated()), id: \.offset) { _, row in
                        GridRow {
                            Text(row.label).foregroundStyle(Theme.textSecondary)
                            Text(row.value).lineLimit(1).truncationMode(.middle)
                        }
                        .font(.system(size: 12))
                    }
                }
            } else {
                Text("Collecting…").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Spacer()
            ToolButton(systemImage: "gearshape", help: "Settings") {
                app.closeMenuPanel()
                WindowManager.shared.openSettings()
            }
            ToolButton(systemImage: "power", help: "Quit Bugbear") {
                NSApp.terminate(nil)
            }
        }
        .padding(8)
    }

    private func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}

struct MenuRow: View {
    let systemImage: String
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .frame(width: 18)
                Text(title).font(.system(size: 13))
                Spacer()
                Text(shortcut).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(hovering ? Theme.control : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
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
            .background(isOn ? Theme.accentSoft : Theme.control)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isOn ? Color.clear : Theme.borderStrong, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
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
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderStrong, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
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
                                    .help(info.dayPart.title)
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
