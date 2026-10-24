import BugbearCore
import SwiftUI

/// Top-right corner of the menu panel: appears when the GitHub repository has new commits.
/// It sits in the header so the panel keeps its height.
struct UpdateBadge: View {
    @State private var updater = Updater.shared
    @State private var showsDetails = false

    var body: some View {
        switch updater.state {
        case .available(let info):
            Button {
                showsDetails = true
            } label: {
                Label("Update · \(info.newCommitCount)", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(Theme.accentText)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("A new version is available")
            .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                details(info)
            }
        case .updating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Updating…").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            .help("Pulling and building the new version. The app restarts when it is ready.")
        case .failed(let message):
            Button {
                showsDetails = true
            } label: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            }
            .buttonStyle(.plain)
            .help(message)
            .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                failure(message)
            }
        default:
            EmptyView()
        }
    }

    private func details(_ info: UpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(info.newCommitCount == 1 ? "1 new change" : "\(info.newCommitCount) new changes")
                .font(.system(size: 13, weight: .bold))
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(info.changes.enumerated()), id: \.offset) { _, change in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(Theme.textSecondary)
                        Text(change.title).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 12))
                }
                if info.newCommitCount > info.changes.count {
                    Text("and \(info.newCommitCount - info.changes.count) more")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text("Pulls the source, builds it on this Mac (1-2 minutes) and restarts the app.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Later") { showsDetails = false }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Update now") {
                    showsDetails = false
                    updater.update()
                }
                .buttonStyle(AccentButtonStyle())
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Update").font(.system(size: 13, weight: .bold))
            Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Show log") { updater.showLog() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Check again") {
                    showsDetails = false
                    Task { await updater.check(userInitiated: true) }
                }
                .buttonStyle(AccentButtonStyle())
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// Settings → Updates.
struct UpdateSettingsSection: View {
    @State private var updater = Updater.shared
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Section("Updates") {
            HStack {
                Text("Version")
                Spacer()
                Text(updater.versionText).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
            }
            HStack {
                Text("What's new")
                Spacer()
                Button("Show…") { WhatsNewTracker.openLatest() }
            }
            if updater.canCheck {
                Toggle("Check GitHub for new versions", isOn: $settings.checkForUpdates)
                HStack {
                    Text(statusText).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Check now") { Task { await updater.check(userInitiated: true) } }
                        .disabled(updater.state == .checking || updater.state == .updating)
                }
            } else {
                Text("Updates work for copies built from a git clone of a GitHub repository, as scripts/install.sh does. This copy has no repository or commit to compare.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .onChange(of: settings.checkForUpdates) { updater.start() }
    }

    private var statusText: String {
        switch updater.state {
        case .checking: return "Checking…"
        case .upToDate: return "Up to date"
        case .available(let info): return "\(info.newCommitCount) new changes, see the menu bar panel"
        case .updating: return "Updating…"
        case .failed(let message): return message
        case .idle:
            if let checked = updater.lastChecked {
                return "Last checked \(checked.formatted(date: .omitted, time: .shortened))"
            }
            return "Checks every 6 hours"
        }
    }
}
