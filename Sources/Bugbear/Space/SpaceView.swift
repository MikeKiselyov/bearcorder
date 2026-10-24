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
                        .fill(fraction > 0.9 ? Theme.accent : Theme.textSecondary)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 8)
        }
    }
}

/// One cleanable thing with its size and a two-step Delete (click, then confirm).
struct CleanupRow: View {
    @Bindable var model: SpaceModel
    let category: CleanupCategory
    var compact = false

    var body: some View {
        let bytes = model.sizes[category.id] ?? 0
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: category.symbol)
                .font(.system(size: 15))
                .foregroundStyle(Theme.accentSoft)
                .frame(width: 22)
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
        .padding(.vertical, compact ? 6 : 10)
    }

    @ViewBuilder
    private var actions: some View {
        switch category.action {
        case .openCaptures:
            Button("Open") {
                WindowManager.shared.openHistory()
            }
            .buttonStyle(SecondaryButtonStyle())
        case .deleteContents:
            if model.cleaningID == category.id {
                ProgressView().controlSize(.small).frame(width: 60)
            } else if model.confirmingID == category.id {
                HStack(spacing: 6) {
                    Button("Cancel") { model.confirmingID = nil }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Delete") {
                        Task { await model.clean(category) }
                    }
                    .buttonStyle(AccentButtonStyle())
                }
            } else {
                Button("Clean") { model.confirmingID = category.id }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled((model.sizes[category.id] ?? 0) == 0 || model.cleaningID != nil)
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
        .background(Theme.window)
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
        case .running(let progress):
            scanProgress(progress)
        case .done:
            folderList
        }
    }

    private var scanPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("See what takes space in your home folder").font(.system(size: 15, weight: .semibold))
            Text("Bugbear adds up every folder and finds the biggest files. It takes a minute or two. macOS may ask once for Desktop, Documents and Downloads; other apps' private data, Apple's own folders and the Photos and Music libraries are skipped.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Scan home folder") { model.startScan() }
                .buttonStyle(AccentButtonStyle())
        }
    }

    private func scanProgress(_ progress: DiskScanner.Progress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Scanning… \(progress.files) files, \(SpaceModel.format(progress.bytes))")
                    .font(.system(size: 13, weight: .semibold))
            }
            if !progress.folder.isEmpty {
                Text("In ~/\(progress.folder)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Button("Stop") { model.cancelScan() }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    @ViewBuilder
    private var folderList: some View {
        if let folder = model.currentFolder {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Button("Home") { model.folderPath = [] }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.link)
                    ForEach(Array(model.folderPath.enumerated()), id: \.offset) { item in
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                        Button(item.element) {
                            model.folderPath = Array(model.folderPath.prefix(item.offset + 1))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(item.offset == model.folderPath.count - 1 ? Theme.text : Theme.link)
                    }
                    Spacer()
                    Text(SpaceModel.format(folder.bytes)).font(.system(size: 13, design: .monospaced))
                    Button("Show in Finder") { model.reveal(model.url(forFolder: model.folderPath)) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Scan again") { model.startScan() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .font(.system(size: 13))
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(folder.children, id: \.name) { child in
                            folderRow(child, parentBytes: folder.bytes)
                            Divider().overlay(Theme.border)
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
                Text("In Library only app data, caches, developer files and logs are counted. Skipped, because it is macOS's own data or macOS asks for permission: other apps' private data, Apple's folders, the Photos and Music libraries, the Trash.")
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
    }

    // MARK: Largest files

    @ViewBuilder
    private var largest: some View {
        switch model.scanState {
        case .idle:
            scanPrompt
        case .running(let progress):
            scanProgress(progress)
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
            if model.confirmingFile == file.path {
                Button("Cancel") { model.confirmingFile = nil }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Move") { model.moveToTrash(file.path) }
                    .buttonStyle(AccentButtonStyle())
            } else {
                Button("Move to Trash") { model.confirmingFile = file.path }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.vertical, 8)
    }
}

/// The Space tab in the menu bar panel: disk bar, the biggest cleanable things, and the window.
struct SpaceTabSection: View {
    @State private var model = SpaceModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DiskBar(total: model.volumeTotal, free: model.volumeFree)
            HStack {
                SectionLabel("Can be cleaned")
                Spacer()
                if model.isMeasuring {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(SpaceModel.format(model.cleanableBytes))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(model.visibleCategories.prefix(5))) { category in
                    CleanupRow(model: model, category: category, compact: true)
                }
            }
            if let message = model.message {
                Text(message).font(.system(size: 11)).foregroundStyle(Theme.success).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("All categories") { WindowManager.shared.openSpace(section: .cleanUp) }
                    .buttonStyle(SecondaryButtonStyle())
                Button("What takes space…") { WindowManager.shared.openSpace(section: .folders) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(16)
        .task {
            await model.measure()
        }
    }
}
