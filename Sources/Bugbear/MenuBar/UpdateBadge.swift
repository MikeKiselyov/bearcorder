import BugbearCore
import SwiftUI

/// Top-right corner of the menu panel: appears when GitHub has a newer release.
/// It sits in the header so the panel keeps its height.
struct UpdateBadge: View {
    @State private var updater = Updater.shared
    @State private var showsDetails = false
    /// Draws the list of changes in place of the badge, for snapshots (the popover is not drawn there).
    var detailsOnly = false

    /// "#9 Pick screenshot and video quality" for a pull request, the title for a commit.
    private func changeLabel(_ change: UpdateInfo.Change) -> String {
        guard let number = change.pullRequest else { return change.title }
        return "#\(number) \(change.title)"
    }

    var body: some View {
        switch updater.state {
        case .available(let info) where detailsOnly:
            details(info)
        case .available(let info):
            Button {
                showsDetails = true
            } label: {
                Label("Update to \(info.version)", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(Theme.accentText)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .tip("Version \(info.version) is available, you have \(updater.version)")
            .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                details(info)
            }
        case .updating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Updating…").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            .tip("Pulling and building the new version. The app restarts when it is ready.")
        case .failed(let message):
            Button {
                showsDetails = true
            } label: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            }
            .buttonStyle(.plain)
            .tip(message)
            .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                failure(message)
            }
        default:
            EmptyView()
        }
    }

    private func details(_ info: UpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Version \(info.version)")
                .font(.system(size: 13, weight: .bold))
            Text(info.changeCount == 1 ? "You have \(updater.version). 1 change since then:" : "You have \(updater.version). \(info.changeCount) changes since then:")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(info.changes.enumerated()), id: \.offset) { _, change in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(Theme.textSecondary)
                        if let url = change.url(repository: updater.repository) {
                            Link(destination: url) {
                                Text(changeLabel(change)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(Theme.link)
                            .tip("Open on GitHub: \(url.absoluteString)")
                        } else {
                            Text(changeLabel(change)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .font(.system(size: 12))
                }
                if info.changeCount > info.changes.count {
                    Text("and \(info.changeCount - info.changes.count) more")
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
                    .tip("Close this and update another time")
                Button("Update now") {
                    showsDetails = false
                    updater.update()
                }
                .buttonStyle(AccentButtonStyle())
                .tip("Pull, build and install the new version, then restart Bugbear")
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
                    .tip("Open the update log to see what went wrong")
                Spacer()
                Button("Check again") {
                    showsDetails = false
                    Task { await updater.check(userInitiated: true) }
                }
                .buttonStyle(AccentButtonStyle())
                .tip("Try checking GitHub for a new version again")
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
                    .tip("Show what changed in this version")
            }
            if updater.canCheck {
                Toggle("Check GitHub for new versions", isOn: $settings.checkForUpdates)
                    .tip("Check for a newer Bugbear release every 6 hours and show a badge in the menu bar panel")
                HStack {
                    Text(statusText).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button("Check now") { Task { await updater.check(userInitiated: true) } }
                        .disabled(updater.state == .checking || updater.state == .updating)
                        .tip("Check GitHub for a new version right now")
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
        case .available(let info): return "\(info.changeCount) new changes, see the menu bar panel"
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
