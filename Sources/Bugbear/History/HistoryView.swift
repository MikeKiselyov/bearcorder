import AppKit
import SwiftUI

/// All saved captures with search and filters.
struct HistoryView: View {
    @Environment(AppState.self) private var app
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var pendingDelete: Capture?
    @State private var selecting = false
    @State private var selected: Set<UUID> = []

    private var selectedCaptures: [Capture] {
        var result: [Capture] = []
        for capture in app.store.captures where selected.contains(capture.id) {
            result.append(capture)
        }
        return result
    }

    private var canMakeGuide: Bool {
        let chosen = selectedCaptures
        if chosen.isEmpty { return false }
        for capture in chosen where capture.kind != .screenshot {
            return false
        }
        return true
    }

    private var canCompare: Bool {
        let chosen = selectedCaptures
        return chosen.count == 2 && chosen[0].kind == chosen[1].kind
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case screenshots = "Screenshots"
        case videos = "Videos"

        var id: String { rawValue }
    }

    private var filtered: [Capture] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        var result: [Capture] = []
        for capture in app.store.captures {
            if filter == .screenshots && capture.kind != .screenshot { continue }
            if filter == .videos && capture.kind != .video { continue }
            if !query.isEmpty && !capture.searchText.contains(query) { continue }
            result.append(capture)
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    TextField("Search by app, URL…", text: $search).textFieldStyle(.plain)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .frame(width: 280, height: 32)
                .background(Color(hex: 0x26282C))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                PillPicker(options: Filter.allCases, selection: $filter) { value in value.rawValue }
                    .frame(width: 300)
                Spacer()
                if selecting {
                    Text("\(selected.count) selected").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    Button("Step guide") { WindowManager.shared.openStepGuide(captures: selectedCaptures) }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(!canMakeGuide)
                        .help("Put the selected screenshots into one numbered guide (PNG or PDF)")
                    Button("Compare") {
                        let chosen = selectedCaptures
                        WindowManager.shared.openCompare(chosen[0], chosen[1])
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!canCompare)
                    .help("Pick two screenshots or two clips: before and after")
                    Button("Done") {
                        selecting = false
                        selected = []
                    }
                    .buttonStyle(AccentButtonStyle())
                } else {
                    Text("\(filtered.count) captures").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    Button("Select") { selecting = true }
                        .buttonStyle(SecondaryButtonStyle())
                        .help("Select captures for a step guide or a before/after comparison")
                }
                Button {
                    NSWorkspace.shared.open(AppPaths.captures)
                } label: {
                    Label("Open folder", systemImage: "folder")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 36)
            .padding(.bottom, 12)
            Divider().overlay(Theme.border)

            if filtered.isEmpty {
                VStack(spacing: 10) {
                    LogoView(size: 64)
                    Text(app.store.captures.isEmpty ? "No captures yet" : "Nothing matches")
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(HotKeySettings.shared.text(for: .screenshotArea)) takes a screenshot, \(HotKeySettings.shared.text(for: .saveMinute)) saves the last minute of the screen.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)], spacing: 16) {
                        ForEach(filtered) { capture in
                            card(capture)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.window)
        .confirmationDialog("Delete this capture?", isPresented: Binding(get: { pendingDelete != nil }, set: { value in if !value { pendingDelete = nil } }), presenting: pendingDelete) { capture in
            Button("Delete", role: .destructive) {
                WindowManager.shared.close(id: "\(capture.kind == .screenshot ? "screenshot" : "video"):\(capture.id)")
                app.store.delete(capture)
            }
        } message: { _ in
            Text("The original and all edits are removed. Exported files stay where you saved them.")
        }
    }

    private func card(_ capture: Capture) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CaptureThumbnail(capture: capture, height: 130)
                .overlay(alignment: .topLeading) {
                    if selecting {
                        Image(systemName: selected.contains(capture.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(selected.contains(capture.id) ? Theme.accent : Color.white)
                            .shadow(radius: 2)
                            .padding(8)
                    }
                }
            HStack(spacing: 6) {
                Image(systemName: capture.kind == .screenshot ? "photo" : "video")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Text(capture.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                Menu {
                    Button("Open") { WindowManager.shared.openEditor(for: capture) }
                    Button("Show original in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([capture.mediaURL])
                    }
                    Button("Copy bug report (Markdown)") {
                        BugReportBuilder.copy(for: capture, timeMap: nil, files: [capture.mediaURL], format: .markdown)
                    }
                    Button("Copy bug report (Jira wiki)") {
                        BugReportBuilder.copy(for: capture, timeMap: nil, files: [capture.mediaURL], format: .jira)
                    }
                    Button("Copy environment") {
                        copyToClipboard(capture.environment.markdown())
                    }
                    if FileManager.default.fileExists(atPath: capture.systemLogURL.path) {
                        Button("Open system log") { NSWorkspace.shared.open(capture.systemLogURL) }
                    }
                    if FileManager.default.fileExists(atPath: capture.crashReportURL.path) {
                        Button("Open crash report") { NSWorkspace.shared.open(capture.crashReportURL) }
                    }
                    Divider()
                    Button("Delete…", role: .destructive) { pendingDelete = capture }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("More actions")
            }
            if !capture.environment.url.isEmpty {
                Text(capture.environment.url)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(capture.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(10)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent, lineWidth: selecting && selected.contains(capture.id) ? 2 : 0))
        .onTapGesture(count: 2) {
            WindowManager.shared.openEditor(for: capture)
        }
        .onTapGesture {
            if !selecting { return }
            if selected.contains(capture.id) {
                selected.remove(capture.id)
            } else {
                selected.insert(capture.id)
            }
        }
        .onDrag {
            NSItemProvider(contentsOf: capture.mediaURL) ?? NSItemProvider()
        }
    }
}
