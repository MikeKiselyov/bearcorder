import AppKit
import SwiftUI

/// What the "More actions" menu of a capture card offers, in its order.
enum HistoryCardAction: CaseIterable {
    case open
    case reveal
    case copyMarkdown
    case copyJira
    case copyEnvironment
    case systemLog
    case crashReport
    case delete

    /// The menu item's text.
    var title: String {
        switch self {
        case .open: return L("history.card.action.open")
        case .reveal: return L("history.card.action.reveal")
        case .copyMarkdown: return L("history.card.action.copyMarkdown")
        case .copyJira: return L("history.card.action.copyJira")
        case .copyEnvironment: return L("history.card.action.copyEnvironment")
        case .systemLog: return L("history.card.action.systemLog")
        case .crashReport: return L("history.card.action.crashReport")
        case .delete: return L("history.card.action.delete")
        }
    }

    /// The actions this capture has: the log and crash report only when they were saved.
    @MainActor
    static func available(for capture: Capture) -> [HistoryCardAction] {
        var result: [HistoryCardAction] = []
        for action in allCases {
            if action == .systemLog && !FileManager.default.fileExists(atPath: capture.systemLogURL.path) { continue }
            if action == .crashReport && !FileManager.default.fileExists(atPath: capture.crashReportURL.path) { continue }
            result.append(action)
        }
        return result
    }

    /// Does what the menu item does; Delete only asks first.
    @MainActor
    func perform(on capture: Capture) {
        switch self {
        case .open:
            WindowManager.shared.openEditor(for: capture)
        case .reveal:
            SystemActions.reveal([capture.mediaURL])
        case .copyMarkdown:
            BugReportBuilder.copy(for: capture, timeMap: nil, format: .markdown)
        case .copyJira:
            BugReportBuilder.copy(for: capture, timeMap: nil, format: .jira)
        case .copyEnvironment:
            copyToClipboard(capture.environment.markdown())
        case .systemLog:
            SystemActions.open(capture.systemLogURL)
        case .crashReport:
            SystemActions.open(capture.crashReportURL)
        case .delete:
            HistoryState.shared.pendingDelete = capture
        }
    }
}

/// History state that lives outside the view, so tests can reach the "Delete?" question.
@MainActor
@Observable
final class HistoryState {
    static let shared = HistoryState()
    var pendingDelete: Capture?
}

/// All saved captures: kinds and apps in the sidebar, captures by day, search on top.
struct HistoryView: View {
    @Environment(AppState.self) private var app
    @Bindable private var state = HistoryState.shared
    @State private var search = ""
    @State private var filter: Filter = .all
    /// Only captures of this app, when one is picked in the sidebar.
    @State private var appFilter: String?
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
        case all
        case screenshots
        case videos

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return L("history.filter.all")
            case .screenshots: return L("history.filter.screenshots")
            case .videos: return L("history.filter.videos")
            }
        }

        /// What the sidebar row shows when picked.
        var tip: String {
            switch self {
            case .all: return L("history.filter.all.tip")
            case .screenshots: return L("history.filter.screenshots.tip")
            case .videos: return L("history.filter.videos.tip")
            }
        }

        var symbol: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .screenshots: return "photo"
            case .videos: return "video"
            }
        }

        var tint: TileTint {
            switch self {
            case .all: return .gray
            case .screenshots: return .coral
            case .videos: return .pink
            }
        }
    }

    private var filtered: [Capture] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        var result: [Capture] = []
        for capture in app.store.captures {
            if filter == .screenshots && capture.kind != .screenshot { continue }
            if filter == .videos && capture.kind != .video { continue }
            if let name = appFilter, capture.title != name { continue }
            if !query.isEmpty && !capture.searchText.contains(query) { continue }
            result.append(capture)
        }
        return result
    }

    private func count(_ kind: Filter) -> Int {
        var total = 0
        for capture in app.store.captures {
            if kind == .screenshots && capture.kind != .screenshot { continue }
            if kind == .videos && capture.kind != .video { continue }
            total += 1
        }
        return total
    }

    /// The apps with the most captures, for the sidebar.
    private var topApps: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for capture in app.store.captures {
            counts[capture.title, default: 0] += 1
        }
        var list: [(name: String, count: Int)] = []
        for (name, total) in counts {
            list.append((name: name, count: total))
        }
        // Equal counts go by name, so the list does not reshuffle between launches.
        list.sort { first, second in
            if first.count != second.count {
                return first.count > second.count
            }
            return first.name < second.name
        }
        return Array(list.prefix(6))
    }

    /// Captures grouped by the day they were taken, newest day first.
    private var days: [(title: String, captures: [Capture])] {
        var groups: [(title: String, captures: [Capture])] = []
        let calendar = Calendar.current
        for capture in filtered {
            let title = dayTitle(capture.createdAt, calendar: calendar)
            if let last = groups.last, last.title == title {
                groups[groups.count - 1].captures.append(capture)
            } else {
                groups.append((title: title, captures: [capture]))
            }
        }
        return groups
    }

    private func dayTitle(_ date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return L("history.day.today") }
        if calendar.isDateInYesterday(date) { return L("history.day.yesterday") }
        return date.formatted(date: .complete, time: .omitted)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.border).frame(width: 1)
            VStack(spacing: 0) {
                toolbar
                if filtered.isEmpty {
                    VStack(spacing: 10) {
                        LogoView(size: 64)
                        Text(app.store.captures.isEmpty ? L("history.empty.noCaptures") : L("history.empty.noMatches"))
                            .font(.system(size: 15, weight: .semibold))
                        Text(L("history.empty.hint", HotKeySettings.shared.text(for: .screenshotArea), HotKeySettings.shared.text(for: .saveMinute)))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(days, id: \.title) { day in
                                Text(day.title)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.textSecondary)
                                    .padding(.top, 4)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 14)], spacing: 14) {
                                    ForEach(day.captures) { capture in
                                        card(capture)
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
                if selecting {
                    selectionBar
                }
            }
        }
        .foregroundStyle(Theme.text)
        .auroraBackground()
        .onChange(of: app.store.captures.count) {
            // The picked app's last capture was deleted: show everything again.
            if let name = appFilter, !topApps.contains(where: { item in item.name == name }) {
                appFilter = nil
            }
        }
        .confirmationDialog(L("history.delete.question"), isPresented: Binding(get: { state.pendingDelete != nil }, set: { value in if !value { state.pendingDelete = nil } }), presenting: state.pendingDelete) { capture in
            Button(L("history.delete.confirm"), role: .destructive) {
                WindowManager.shared.close(id: "\(capture.kind == .screenshot ? "screenshot" : "video"):\(capture.id)")
                app.store.delete(capture)
            }
        } message: { _ in
            Text(L("history.delete.message"))
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Filter.allCases) { kind in
                sidebarRow(title: kind.title, count: count(kind), isSelected: filter == kind && appFilter == nil) {
                    IconTile(systemImage: kind.symbol, tint: kind.tint, size: 22)
                } action: {
                    filter = kind
                    appFilter = nil
                }
                .accessibilityLabel(kind.title)
                .tip(kind.tip)
            }
            if !topApps.isEmpty {
                SectionLabel(L("history.sidebar.apps"))
                    .padding(.horizontal, 8)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                ForEach(topApps, id: \.name) { item in
                    sidebarRow(title: item.name, count: item.count, isSelected: appFilter == item.name) {
                        EmptyView()
                    } action: {
                        filter = .all
                        appFilter = item.name
                    }
                    .accessibilityLabel(L("history.sidebar.app", item.name))
                    .tip(L("history.sidebar.app.tip", item.name))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 44)
        .frame(width: 200)
        .background(Theme.sidebar)
    }

    private func sidebarRow<Icon: View>(title: String, count: Int, isSelected: Bool, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                icon()
                Text(title).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
            .foregroundStyle(isSelected ? Theme.text : Theme.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(isSelected ? Theme.controlSelected : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField(L("history.search.placeholder"), text: $search).textFieldStyle(.plain)
                    .tip(L("history.search.tip"))
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(maxWidth: 320)
            .frame(height: 32)
            .background(Theme.control)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            Spacer()
            Text(L("history.count", filtered.count)).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            if !selecting {
                Button(L("history.select")) { selecting = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .tip(L("history.select.tip"))
            }
            Button {
                SystemActions.open(AppPaths.captures)
            } label: {
                Label(L("history.openFolder"), systemImage: "folder")
            }
            .buttonStyle(SecondaryButtonStyle())
            .tip(L("history.openFolder.tip"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 36)
        .padding(.bottom, 10)
    }

    /// While selecting: what can be done with the picked captures, at the bottom.
    private var selectionBar: some View {
        HStack(spacing: 8) {
            Text(L("history.selection.count", selected.count)).font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(L("history.selection.stepGuide")) { WindowManager.shared.openStepGuide(captures: selectedCaptures) }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!canMakeGuide)
                .tip(L("history.selection.stepGuide.tip"))
            Button(L("history.selection.compare")) {
                let chosen = selectedCaptures
                WindowManager.shared.openCompare(chosen[0], chosen[1])
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!canCompare)
            .tip(L("history.selection.compare.tip"))
            Button(L("history.selection.done")) {
                selecting = false
                selected = []
            }
            .buttonStyle(AccentButtonStyle())
            .tip(L("history.selection.done.tip"))
        }
        .padding(10)
        .glassCard()
        .padding(12)
    }

    private func card(_ capture: Capture) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CaptureThumbnail(capture: capture, height: 130)
                // VoiceOver (and the tests) press the picture: it opens the capture, or picks it
                // while selecting, like a click does.
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                // The time tells apart captures of the same app.
                .accessibilityLabel(cardLabel(capture))
                .accessibilityAction { cardPressed(capture, open: !selecting) }
                .overlay(alignment: .topLeading) {
                    if selecting {
                        Image(systemName: selected.contains(capture.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(selected.contains(capture.id) ? Theme.accent : Color.white)
                            .shadow(radius: 2)
                            .padding(8)
                    } else {
                        Text(capture.kind == .screenshot ? L("history.card.kind.screenshot") : L("history.card.kind.clip"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
            HStack(spacing: 6) {
                Text(capture.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                Menu {
                    ForEach(HistoryCardAction.available(for: capture), id: \.self) { action in
                        if action == .delete {
                            Divider()
                            Button(action.title, role: .destructive) { action.perform(on: capture) }
                        } else {
                            Button(action.title) { action.perform(on: capture) }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel(L("history.card.moreActions"))
                .tip(L("history.card.moreActions.tip"))
            }
            if !capture.environment.url.isEmpty {
                Text(capture.environment.url)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(8)
        .glassCard(cornerRadius: 14)
        .contentShape(Rectangle())
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent, lineWidth: selecting && selected.contains(capture.id) ? 2 : 0))
        .tip(L("history.card.tip"))
        .onTapGesture(count: 2) {
            cardPressed(capture, open: true)
        }
        .onTapGesture {
            cardPressed(capture, open: false)
        }
        .onDrag {
            NSItemProvider(contentsOf: capture.mediaURL) ?? NSItemProvider()
        }
    }

    /// What VoiceOver (and the tests) read for a card: the kind, the app and the time, which tells
    /// apart captures of the same app.
    private func cardLabel(_ capture: Capture) -> String {
        let time = capture.createdAt.formatted(date: .abbreviated, time: .standard)
        if capture.kind == .screenshot {
            return L("history.card.label.screenshot", capture.title, time)
        }
        return L("history.card.label.clip", capture.title, time)
    }

    /// A double-click opens the capture; a click while selecting picks it or drops it.
    private func cardPressed(_ capture: Capture, open: Bool) {
        if open {
            WindowManager.shared.openEditor(for: capture)
            return
        }
        if !selecting { return }
        if selected.contains(capture.id) {
            selected.remove(capture.id)
        } else {
            selected.insert(capture.id)
        }
    }
}
