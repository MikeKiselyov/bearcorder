import BugbearCore
import SwiftUI

/// How full the disk is: used and free, as a bar.
struct DiskBar: View {
    var total: Int64
    var free: Int64

    var body: some View {
        let used = max(0, total - free)
        let fraction = total > 0 ? Double(used) / Double(total) : 0
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(SpaceModel.format(free)) free").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(SpaceModel.format(used)) of \(SpaceModel.format(total)) used")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Theme.control)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(fraction > 0.9 ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xDDB2F5), Color(hex: 0x9B5FC9)], startPoint: .leading, endPoint: .trailing)))
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 8)
        }
    }
}

/// The disk as a ring: the biggest clean-up categories in their colors, the rest of what is
/// used, and the free part, with the free space in the middle.
struct DiskRing: View {
    struct Part {
        var bytes: Int64
        var tint: TileTint
    }

    var total: Int64
    var free: Int64
    var parts: [Part]

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.05), lineWidth: 14)
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                Circle()
                    .trim(from: segment.start, to: segment.end)
                    .stroke(segment.style, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 1) {
                Text(SpaceModel.format(free)).font(.system(size: 20, weight: .bold))
                Text("free of \(SpaceModel.format(total))").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: 140, height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(SpaceModel.format(free)) free of \(SpaceModel.format(total))")
    }

    private var segments: [(start: CGFloat, end: CGFloat, style: AnyShapeStyle)] {
        var result: [(start: CGFloat, end: CGFloat, style: AnyShapeStyle)] = []
        if total <= 0 { return result }
        var position: CGFloat = 0
        var partsBytes: Int64 = 0
        let used = CGFloat(max(0, total - free)) / CGFloat(total)
        for part in parts where part.bytes > 0 {
            // Categories can overlap or sit on another disk: never draw past what is used.
            let length = min(CGFloat(part.bytes) / CGFloat(total), max(0, used - position))
            if length <= 0 { break }
            // A thin gap between parts so neighbours stay apart.
            result.append((start: position, end: position + max(0.004, length - 0.004), style: AnyShapeStyle(part.tint.color)))
            position += length
            partsBytes += part.bytes
        }
        let otherUsed = max(0, total - free - partsBytes)
        let otherLength = CGFloat(otherUsed) / CGFloat(total)
        result.append((start: position, end: position + otherLength, style: AnyShapeStyle(Color.white.opacity(0.18))))
        return result
    }
}

/// One cleanable thing with its size and a two-step Delete (click, then confirm).
struct CleanupRow: View {
    @Bindable var model: SpaceModel
    let category: CleanupCategory
    var compact = false
    var tint: TileTint = .coral

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row
            if model.confirmingID == category.id && model.cleaningID != category.id {
                confirmation
            }
        }
        .padding(.vertical, compact ? 6 : 10)
    }

    private var row: some View {
        let bytes = model.sizes[category.id] ?? 0
        return HStack(alignment: compact ? .center : .top, spacing: 12) {
            IconTile(systemImage: category.symbol, tint: tint, size: compact ? 26 : 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title).font(.system(size: 13, weight: .semibold))
                if !compact {
                    Text(category.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(model.isMeasuring && model.sizes[category.id] == nil ? "…" : SpaceModel.format(bytes))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
            actions
        }
    }

    /// Asked after Clean, on its own line so the buttons keep their full names: what goes, how
    /// much, and that it cannot be undone.
    private var confirmation: some View {
        let size = SpaceModel.format(model.sizes[category.id] ?? 0)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Delete \(size) from \(category.title)? This cannot be undone.")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel") { model.confirmingID = nil }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .tip("Keep these files")
                Button("Delete \(size)") {
                    Task { await model.clean(category) }
                }
                .buttonStyle(AccentButtonStyle())
                .tip("Delete for good; this cannot be undone")
            }
        }
        .padding(10)
        .background(Theme.control)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var actions: some View {
        switch category.action {
        case .openCaptures:
            Button("Open") {
                WindowManager.shared.openHistory()
            }
            .buttonStyle(SecondaryButtonStyle())
            .tip("Open the captures history to delete screenshots and clips you no longer need")
        case .deleteContents:
            if model.cleaningID == category.id {
                ProgressView().controlSize(.small).frame(width: 60)
            } else {
                Button("Clean") { model.confirmingID = category.id }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityLabel("Clean \(category.title)")
                    .disabled((model.sizes[category.id] ?? 0) == 0 || model.cleaningID != nil || model.confirmingID == category.id)
                    .tip("Delete the contents of \(category.title) to free space; asks to confirm first")
            }
        }
    }
}

/// The Disk Space window: clean up, folders by size, largest files.
struct SpaceView: View {
    enum Section: String, CaseIterable, Identifiable {
        case cleanUp = "Clean up"
        case folders = "Folders"
        case largest = "Largest files"

        var id: String { rawValue }
    }

    @State private var model = SpaceModel.shared
    @State private var section: Section

    init(section: Section = .cleanUp) {
        _section = State(initialValue: section)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DiskBar(total: model.volumeTotal, free: model.volumeFree)
            HStack {
                Picker(selection: $section) {
                    ForEach(Section.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .tip("Switch between safe clean-up, folders by size and the largest files")
                Spacer()
                if let message = model.message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.success)
                        .lineLimit(2)
                }
            }
            Divider().overlay(Theme.border)
            switch section {
            case .cleanUp:
                cleanUp
            case .folders:
                folders
            case .largest:
                largest
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 44)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Theme.text)
        .auroraBackground()
        .task {
            await model.measure()
        }
    }

    // MARK: Clean up

    private var cleanUp: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(SpaceModel.format(model.cleanableBytes)) can be cleaned safely")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if model.isMeasuring {
                    ProgressView().controlSize(.small)
                }
                Button("Measure again") {
                    Task { await model.measure(force: true) }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.isMeasuring)
                .tip("Measure the clean-up categories again to get fresh sizes")
            }
            Text("Caches are made again by apps when they need them. Deleting them cannot be undone, so each one asks first.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.visibleCategories) { category in
                        CleanupRow(model: model, category: category)
                        Divider().overlay(Theme.border)
                    }
                }
            }
        }
    }

    // MARK: Folders

    @ViewBuilder
    private var folders: some View {
        switch model.scanState {
        case .idle:
            scanPrompt
        case .preparing, .running:
            scanStatus
        case .done:
            folderList
        }
    }

    private var scanPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("See what takes space on this Mac").font(.system(size: 15, weight: .semibold))
            Text("\(AppInfo.name) adds up every folder and finds the biggest files. It takes a minute or two. macOS may ask once for Desktop, Documents and Downloads; other apps' private data, Apple's own folders and the Photos and Music libraries are skipped.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Include other apps' private data (Docker, Slack, Telegram…). macOS asks once.", isOn: $model.includeAppData)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .tip("Also count other apps' data folders in the scan; macOS asks for permission once")
            Button("Scan home folder and Applications") { model.startScan() }
                .buttonStyle(AccentButtonStyle())
                .tip("Add up every folder and find the biggest files; takes a minute or two")
        }
    }

    /// Steps of the scan: permissions first, then the home folder and Applications, with live numbers.
    private var scanStatus: some View {
        var progress = DiskScanner.Progress()
        var isPreparing = true
        if case .running(let current) = model.scanState {
            progress = current
            isPreparing = false
        }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(isPreparing ? "Checking access…" : "Scanning…").font(.system(size: 15, weight: .semibold))
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = Int(context.date.timeIntervalSince(model.scanStartedAt))
                    Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                Button("Stop") { model.cancelScan() }
                    .buttonStyle(SecondaryButtonStyle())
                    .tip("Stop the scan")
            }
            VStack(alignment: .leading, spacing: 8) {
                if !model.accessChecks.isEmpty {
                    stepRow("Access to protected folders", done: !isPreparing, active: isPreparing)
                    ForEach(model.accessChecks) { check in
                        accessRow(check)
                    }
                }
                stepRow("Home folder", done: !isPreparing && progress.folder.hasPrefix("Applications"), active: !isPreparing && !progress.folder.hasPrefix("Applications"))
                stepRow("Applications", done: false, active: progress.folder.hasPrefix("Applications"))
            }
            if !isPreparing {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(progress.files) files · \(SpaceModel.format(progress.bytes))")
                        .font(.system(size: 13, design: .monospaced))
                    if !progress.folder.isEmpty {
                        Text("In \(progress.folder)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            if isPreparing {
                Text("macOS asks once for each folder. Allow the ones you want counted; the scan then runs on its own.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if context.date.timeIntervalSince(model.lastScanProgress) > 10 {
                        Label("No progress for a while: macOS is probably asking for permission. Look for a dialog on your screens and answer it; the scan goes on right after.", systemImage: "exclamationmark.bubble")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func stepRow(_ title: String, done: Bool, active: Bool) -> some View {
        HStack(spacing: 8) {
            if active {
                ProgressView().controlSize(.mini).frame(width: 16)
            } else {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Theme.success : Theme.textTertiary)
                    .frame(width: 16)
            }
            Text(title).font(.system(size: 13, weight: active ? .semibold : .regular))
        }
    }

    private func accessRow(_ check: SpaceModel.AccessCheck) -> some View {
        HStack(spacing: 8) {
            switch check.state {
            case .waiting:
                Image(systemName: "circle.dotted").foregroundStyle(Theme.textTertiary).frame(width: 16)
                Text(check.id).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            case .asking:
                ProgressView().controlSize(.mini).frame(width: 16)
                Text("\(check.id): answer the macOS dialog").font(.system(size: 12, weight: .semibold))
            case .allowed:
                Image(systemName: "checkmark").foregroundStyle(Theme.success).frame(width: 16)
                Text("\(check.id): allowed").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            case .denied:
                Image(systemName: "xmark").foregroundStyle(Theme.warning).frame(width: 16)
                Text("\(check.id): not allowed, left out").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.leading, 24)
    }

    @ViewBuilder
    private var folderList: some View {
        if let folder = model.currentFolder {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Button("This Mac") { model.folderPath = [] }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.link)
                        .tip("Go back to the top level")
                    ForEach(Array(model.folderPath.enumerated()), id: \.offset) { item in
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                        Button(item.element) {
                            model.folderPath = Array(model.folderPath.prefix(item.offset + 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back to \(item.element)")
                        .foregroundStyle(item.offset == model.folderPath.count - 1 ? Theme.text : Theme.link)
                        .tip("Go back to \(item.element)")
                    }
                    Spacer()
                    Text(SpaceModel.format(folder.bytes)).font(.system(size: 13, design: .monospaced))
                    if let url = model.url(forFolder: model.folderPath) {
                        Button("Show in Finder") { model.reveal(url) }
                            .buttonStyle(SecondaryButtonStyle())
                            .tip("Open this folder in Finder")
                    }
                    Button("Scan again") { model.startScan() }
                        .buttonStyle(SecondaryButtonStyle())
                        .tip("Scan the disk again to get fresh numbers")
                }
                .font(.system(size: 13))
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(folder.children, id: \.name) { child in
                            folderRow(child, parentBytes: folder.bytes)
                            Divider().overlay(Theme.border)
                        }
                        if model.folderPath.isEmpty && model.notCounted > 0 {
                            HStack(spacing: 12) {
                                Image(systemName: "questionmark.folder").foregroundStyle(Theme.textTertiary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Not counted").font(.system(size: 13))
                                    Text("macOS itself, other users, skipped folders, local Time Machine snapshots")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Text(SpaceModel.format(model.notCounted)).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.vertical, 8)
                        }
                        let inFiles = folder.bytes - childrenBytes(folder)
                        if inFiles > 0 {
                            HStack {
                                Text("Files directly in this folder").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text(SpaceModel.format(inFiles)).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                if !model.deniedFolders.isEmpty {
                    Text("Not counted, access not allowed: \(model.deniedFolders.joined(separator: ", ")). Allow it in System Settings → Privacy & Security → Files and Folders → \(AppInfo.name), then scan again.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("In Library only app data, caches, developer files and logs are counted\(model.includeAppData ? ", plus other apps' private data" : ""). Skipped, because it is macOS's own data or macOS asks for permission: Apple's folders, the Photos and Music libraries, Contacts, Calendars, Mail, Messages, the Trash.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func childrenBytes(_ folder: DiskTree.Node) -> Int64 {
        var total: Int64 = 0
        for child in folder.children {
            total += child.bytes
        }
        return total
    }

    private func folderRow(_ child: DiskTree.Node, parentBytes: Int64) -> some View {
        let fraction = parentBytes > 0 ? Double(child.bytes) / Double(parentBytes) : 0
        let canOpen = !child.children.isEmpty
        return Button {
            if canOpen {
                model.folderPath.append(child.name)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").foregroundStyle(Theme.textSecondary)
                Text(child.name).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 12)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.control)
                        RoundedRectangle(cornerRadius: 3).fill(Theme.accentSoft).frame(width: geometry.size.width * fraction)
                    }
                }
                .frame(width: 180, height: 6)
                Text(SpaceModel.format(child.bytes))
                    .font(.system(size: 13, design: .monospaced))
                    .frame(width: 90, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(canOpen ? Theme.textSecondary : Color.clear)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Folder \(child.name), \(SpaceModel.format(child.bytes))")
        .tip(canOpen ? "Open this folder to see what is inside" : "\(child.name) has no subfolders")
    }

    // MARK: Largest files

    @ViewBuilder
    private var largest: some View {
        switch model.scanState {
        case .idle:
            scanPrompt
        case .preparing, .running:
            scanStatus
        case .done:
            if model.topFiles.isEmpty {
                Text("No files over 50 MB.").foregroundStyle(Theme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Files over 50 MB, biggest first. Move to Trash keeps them in the Trash until you empty it.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(model.topFiles, id: \.path) { file in
                                fileRow(file)
                                Divider().overlay(Theme.border)
                            }
                        }
                    }
                }
            }
        }
    }

    private func fileRow(_ file: TopFiles.File) -> some View {
        let url = URL(fileURLWithPath: file.path)
        let homePath = model.home.path
        var folder = url.deletingLastPathComponent().path
        if folder.hasPrefix(homePath) {
            folder = "~" + folder.dropFirst(homePath.count)
        }
        return HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).font(.system(size: 13)).lineLimit(1)
                Text(folder).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Text(SpaceModel.format(file.bytes))
                .font(.system(size: 13, design: .monospaced))
                .frame(width: 90, alignment: .trailing)
            Button("Show") { model.reveal(url) }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Show \(url.lastPathComponent) in Finder")
                .tip("Show this file in Finder")
            if model.confirmingFile == file.path {
                Button("Cancel") { model.confirmingFile = nil }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityLabel("Keep \(url.lastPathComponent)")
                    .tip("Keep this file")
                Button("Move") { model.moveToTrash(file.path) }
                    .buttonStyle(AccentButtonStyle())
                    .accessibilityLabel("Move \(url.lastPathComponent) to the Trash now")
                    .tip("Confirm: move the file to the Trash")
            } else {
                Button("Move to Trash") { model.confirmingFile = file.path }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityLabel("Move \(url.lastPathComponent) to Trash")
                    .tip("Move this file to the Trash; asks to confirm first and you can still restore it from the Trash")
            }
        }
        .padding(.vertical, 8)
    }
}

/// The Space tab in the menu bar panel: disk bar, the biggest cleanable things, and the window.
struct SpaceTabSection: View {
    @State private var model = SpaceModel.shared

    /// Colors for the biggest categories, in the ring and on their rows.
    static let tints: [TileTint] = [.coral, .purple, .blue, .green, .yellow]

    var body: some View {
        let shown = Array(model.visibleCategories.prefix(5))
        VStack(alignment: .leading, spacing: 10) {
            DiskRing(total: model.volumeTotal, free: model.volumeFree, parts: ringParts(shown))
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            HStack {
                SectionLabel("Can be cleaned")
                Spacer()
                if model.isMeasuring {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(SpaceModel.format(model.cleanableBytes))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.accentSoft)
                }
            }
            VStack(spacing: 6) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, category in
                    CleanupRow(model: model, category: category, compact: true, tint: SpaceTabSection.tints[index % SpaceTabSection.tints.count])
                        .padding(.horizontal, 10)
                        .glassCard(cornerRadius: 12)
                }
            }
            if let message = model.message {
                Text(message).font(.system(size: 11)).foregroundStyle(Theme.success).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("All categories") { WindowManager.shared.openSpace(section: .cleanUp) }
                    .buttonStyle(SecondaryButtonStyle())
                    .tip("Open the Disk Space window with every clean-up category")
                Spacer()
                Button("What takes space…") { WindowManager.shared.openSpace(section: .folders) }
                    .buttonStyle(AccentButtonStyle())
                    .tip("Scan folders to see what takes the most space on this Mac")
            }
        }
        .padding(16)
        .task {
            await model.measure()
        }
    }

    private func ringParts(_ categories: [CleanupCategory]) -> [DiskRing.Part] {
        var parts: [DiskRing.Part] = []
        for (index, category) in categories.enumerated() {
            parts.append(DiskRing.Part(bytes: model.sizes[category.id] ?? 0, tint: SpaceTabSection.tints[index % SpaceTabSection.tints.count]))
        }
        return parts
    }
}
