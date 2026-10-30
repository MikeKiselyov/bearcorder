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
                Text(L("space.bar.free", SpaceModel.format(free))).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(L("space.bar.used", SpaceModel.format(used), SpaceModel.format(total)))
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
                Text(L("space.ring.freeOf", SpaceModel.format(total))).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: 140, height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("space.ring.label", SpaceModel.format(free), SpaceModel.format(total)))
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

/// One cleanable thing with its size and Review… (Open for our captures, which are never reviewed here).
struct CleanupRow: View {
    @Bindable var model: SpaceModel
    let category: CleanupCategory
    var compact = false
    var tint: TileTint = .coral
    /// Review…: the window opens the list in place, the menu panel opens the window on it.
    let onReview: () -> Void

    var body: some View {
        let bytes = model.sizes[category.id] ?? 0
        HStack(alignment: compact ? .center : .top, spacing: 12) {
            IconTile(systemImage: category.symbol, tint: tint, size: compact ? 26 : 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(compact ? 2 : nil)
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
        .padding(.vertical, compact ? 6 : 10)
    }

    @ViewBuilder
    private var actions: some View {
        switch category.action {
        case .openCaptures:
            Button(L("space.captures.open")) {
                WindowManager.shared.openHistory()
            }
            .buttonStyle(SecondaryButtonStyle())
            .fixedSize()
            .tip(L("space.captures.open.tip"))
        case .deleteContents:
            Button(L("space.review"), action: onReview)
                .buttonStyle(SecondaryButtonStyle())
                .fixedSize()
                .accessibilityLabel(L("space.review.label", category.title))
                .disabled((model.sizes[category.id] ?? 0) == 0)
                .tip(L("space.review.tip", category.title))
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

        var title: String {
            switch self {
            case .cleanUp: return L("space.section.cleanUp")
            case .folders: return L("space.section.folders")
            case .largest: return L("space.section.largest")
            }
        }
    }

    @State private var model = SpaceModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DiskBar(total: model.volumeTotal, free: model.volumeFree)
            HStack {
                Picker(selection: $model.section) {
                    ForEach(Section.allCases) { item in
                        Text(item.title).tag(item)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .tip(L("space.section.tip"))
                Spacer()
                if let message = model.message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.success)
                        .lineLimit(2)
                }
            }
            Divider().overlay(Theme.border)
            switch model.section {
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

    @ViewBuilder
    private var cleanUp: some View {
        if let id = model.openReviewID {
            reviewPage(id)
        } else {
            categoryList
        }
    }

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("space.cleanable", SpaceModel.format(model.cleanableBytes)))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if model.isMeasuring {
                    ProgressView().controlSize(.small)
                }
                Button(L("space.measureAgain")) {
                    Task { await model.measure(force: true) }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.isMeasuring)
                .tip(L("space.measureAgain.tip"))
            }
            Text(L("space.cleanUp.note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            ScrollView {
                VStack(spacing: 0) {
                    ProjectsRow(model: model) { model.showReview(SpaceModel.projectsID) }
                    Divider().overlay(Theme.border)
                    ForEach(model.visibleCategories) { category in
                        CleanupRow(model: model, category: category) { model.showReview(category.id) }
                        Divider().overlay(Theme.border)
                    }
                }
            }
        }
    }

    /// One review list in place of the categories: projects or a cache category.
    private func reviewPage(_ id: String) -> some View {
        let category = CleanupCategory.all.first { item in item.id == id }
        let isProjects = id == SpaceModel.projectsID
        var title = L("space.projects.title")
        var detail = L("space.projects.detail")
        if let category = category {
            title = category.title
            detail = category.detail
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    model.showReview(nil)
                } label: {
                    Label(L("space.review.back"), systemImage: "chevron.left")
                }
                .buttonStyle(SecondaryButtonStyle())
                .tip(L("space.review.back.tip"))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isProjects {
                    projectControls
                }
            }
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if isProjects {
                projectList
            } else if let review = model.cacheReviews[id] {
                SpaceReviewView(review: review, model: model)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("space.review.listing"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .task(id: id) {
            guard let category = category else {
                if !isProjects {
                    model.showReview(nil)
                }
                return
            }
            if await model.openReview(for: category) == nil {
                model.showReview(nil)
            }
        }
    }

    /// Find projects, or its progress and Stop while it runs.
    @ViewBuilder
    private var projectControls: some View {
        if model.isScanningProjects {
            ProgressView().controlSize(.small)
            Text(L("space.projects.searching"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Button(L("space.projects.stop")) { model.stopProjectScan() }
                .buttonStyle(SecondaryButtonStyle())
                .tip(L("space.projects.stop.tip"))
        } else {
            let removing = model.projectReview?.isRemoving ?? false
            Button(model.projectReview == nil ? L("space.projects.find") : L("space.projects.findAgain")) {
                Task { await model.scanProjects() }
            }
            .buttonStyle(AccentButtonStyle(isEnabled: !removing))
            .disabled(removing)
            .tip(L("space.projects.find.tip"))
        }
    }

    @ViewBuilder
    private var projectList: some View {
        if !model.unreadableProjectRoots.isEmpty {
            Text(L("space.projects.unreadable", unreadableNames))
                .font(.system(size: 11))
                .foregroundStyle(Theme.warning)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        if let review = model.projectReview {
            SpaceReviewView(review: review, model: model)
        } else if !model.isScanningProjects {
            let roots = AppSettings.shared.projectRoots
            Text(roots.isEmpty ? L("space.projects.noRoots") : L("space.projects.prompt", roots.joined(separator: ", ")))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        } else {
            Spacer(minLength: 0)
        }
    }

    /// The project folders that could not be read, by name: "Documents, Desktop".
    private var unreadableNames: String {
        var names: [String] = []
        for url in model.unreadableProjectRoots {
            names.append(url.lastPathComponent)
        }
        return names.joined(separator: ", ")
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
            Text(L("space.scan.title")).font(.system(size: 15, weight: .semibold))
            Text(L("space.scan.note", AppInfo.name))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(L("space.scan.includeAppData"), isOn: $model.includeAppData)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .tip(L("space.scan.includeAppData.tip"))
            Button(L("space.scan.start")) { model.startScan() }
                .buttonStyle(AccentButtonStyle())
                .tip(L("space.scan.start.tip"))
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
                Text(isPreparing ? L("space.scan.checkingAccess") : L("space.scan.scanning")).font(.system(size: 15, weight: .semibold))
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let seconds = Int(context.date.timeIntervalSince(model.scanStartedAt))
                    Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                Button(L("space.scan.stop")) { model.cancelScan() }
                    .buttonStyle(SecondaryButtonStyle())
                    .tip(L("space.scan.stop.tip"))
            }
            VStack(alignment: .leading, spacing: 8) {
                if !model.accessChecks.isEmpty {
                    stepRow(L("space.scan.step.access"), done: !isPreparing, active: isPreparing)
                    ForEach(model.accessChecks) { check in
                        accessRow(check)
                    }
                }
                stepRow(L("space.scan.step.home"), done: !isPreparing && progress.folder.hasPrefix("Applications"), active: !isPreparing && !progress.folder.hasPrefix("Applications"))
                stepRow(L("space.scan.step.applications"), done: false, active: progress.folder.hasPrefix("Applications"))
            }
            if !isPreparing {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("space.scan.progress", progress.files, SpaceModel.format(progress.bytes)))
                        .font(.system(size: 13, design: .monospaced))
                    if !progress.folder.isEmpty {
                        Text(L("space.scan.folder", progress.folder))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            if isPreparing {
                Text(L("space.scan.accessNote"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if context.date.timeIntervalSince(model.lastScanProgress) > 10 {
                        Label(L("space.scan.stalled"), systemImage: "exclamationmark.bubble")
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
                Text(check.title).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            case .asking:
                ProgressView().controlSize(.mini).frame(width: 16)
                Text(L("space.access.asking", check.title)).font(.system(size: 12, weight: .semibold))
            case .allowed:
                Image(systemName: "checkmark").foregroundStyle(Theme.success).frame(width: 16)
                Text(L("space.access.allowed", check.title)).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            case .denied:
                Image(systemName: "xmark").foregroundStyle(Theme.warning).frame(width: 16)
                Text(L("space.access.denied", check.title)).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.leading, 24)
    }

    @ViewBuilder
    private var folderList: some View {
        if let folder = model.currentFolder {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Button(L("space.folders.top")) { model.folderPath = [] }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.link)
                        .tip(L("space.folders.top.tip"))
                    ForEach(Array(model.folderPath.enumerated()), id: \.offset) { item in
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                        Button(item.element) {
                            model.folderPath = Array(model.folderPath.prefix(item.offset + 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("space.folders.back", item.element))
                        .foregroundStyle(item.offset == model.folderPath.count - 1 ? Theme.text : Theme.link)
                        .tip(L("space.folders.back.tip", item.element))
                    }
                    Spacer()
                    Text(SpaceModel.format(folder.bytes)).font(.system(size: 13, design: .monospaced))
                    if let url = model.url(forFolder: model.folderPath) {
                        Button(L("space.folders.showInFinder")) { model.reveal(url) }
                            .buttonStyle(SecondaryButtonStyle())
                            .tip(L("space.folders.showInFinder.tip"))
                    }
                    Button(L("space.folders.scanAgain")) { model.startScan() }
                        .buttonStyle(SecondaryButtonStyle())
                        .tip(L("space.folders.scanAgain.tip"))
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
                                    Text(L("space.folders.notCounted")).font(.system(size: 13))
                                    Text(L("space.folders.notCounted.detail"))
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
                                Text(L("space.folders.filesHere")).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text(SpaceModel.format(inFiles)).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                if !model.deniedFolders.isEmpty {
                    Text(L("space.folders.denied", model.deniedFolders.joined(separator: ", "), AppInfo.name))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(model.includeAppData ? L("space.folders.libraryNote.withAppData") : L("space.folders.libraryNote"))
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
        .accessibilityLabel(L("space.folders.row.label", child.name, SpaceModel.format(child.bytes)))
        .tip(canOpen ? L("space.folders.row.open.tip") : L("space.folders.row.noSubfolders.tip", child.name))
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
                Text(L("space.largest.empty")).foregroundStyle(Theme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("space.largest.note"))
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
            Button(L("space.largest.show")) { model.reveal(url) }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel(L("space.largest.show.label", url.lastPathComponent))
                .tip(L("space.largest.show.tip"))
            if model.confirmingFile == file.path {
                Button(L("space.largest.keep")) { model.confirmingFile = nil }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityLabel(L("space.largest.keep.label", url.lastPathComponent))
                    .tip(L("space.largest.keep.tip"))
                Button(L("space.largest.move")) { model.moveToTrash(file.path) }
                    .buttonStyle(AccentButtonStyle())
                    .accessibilityLabel(L("space.largest.move.label", url.lastPathComponent))
                    .tip(L("space.largest.move.tip"))
            } else {
                Button(L("space.largest.trash")) { model.confirmingFile = file.path }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityLabel(L("space.largest.trash.label", url.lastPathComponent))
                    .tip(L("space.largest.trash.tip"))
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
        // Four categories and the project folders, as many rows as fit without much scrolling.
        let shown = Array(model.visibleCategories.prefix(4))
        VStack(alignment: .leading, spacing: 10) {
            DiskRing(total: model.volumeTotal, free: model.volumeFree, parts: ringParts(shown))
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            HStack {
                SectionLabel(L("space.tab.canBeCleaned"))
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
                    CleanupRow(model: model, category: category, compact: true, tint: SpaceTabSection.tints[index % SpaceTabSection.tints.count]) {
                        WindowManager.shared.openSpace(section: .cleanUp, category: category.id)
                    }
                    .padding(.horizontal, 10)
                    .glassCard(cornerRadius: 12)
                }
                ProjectsRow(model: model, compact: true) {
                    WindowManager.shared.openSpace(section: .cleanUp, category: SpaceModel.projectsID)
                }
                .padding(.horizontal, 10)
                .glassCard(cornerRadius: 12)
            }
            if let message = model.message {
                Text(message).font(.system(size: 11)).foregroundStyle(Theme.success).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button(L("space.tab.allCategories")) { WindowManager.shared.openSpace(section: .cleanUp) }
                    .buttonStyle(SecondaryButtonStyle())
                    .tip(L("space.tab.allCategories.tip"))
                Spacer()
                Button(L("space.tab.whatTakesSpace")) { WindowManager.shared.openSpace(section: .folders) }
                    .buttonStyle(AccentButtonStyle())
                    .tip(L("space.tab.whatTakesSpace.tip"))
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
