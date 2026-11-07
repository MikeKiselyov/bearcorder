import AppCore
import SwiftUI

/// The new version's changes with "Later" and "Update now", under the menu badge and in Settings.
struct UpdateDetails: View {
    let info: UpdateInfo
    /// Closes the popover the list sits in.
    let close: () -> Void
    private let updater = Updater.shared

    /// "#9 Pick screenshot and video quality" for a pull request, the title for a commit.
    private func changeLabel(_ change: UpdateInfo.Change) -> String {
        guard let number = change.pullRequest else { return change.title }
        return "#\(number) \(change.title)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("menubar.update.details.version", info.version))
                .font(.system(size: 13, weight: .bold))
            Text(L("menubar.update.details.changes", updater.version, info.changeCount))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(info.changes.enumerated()), id: \.offset) { _, change in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(Theme.textSecondary)
                        if let url = change.url(repository: updater.repository) {
                            Button {
                                SystemActions.open(url)
                            } label: {
                                Text(changeLabel(change)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.link)
                            .tip(L("menubar.update.details.change.tip", url.absoluteString))
                        } else {
                            Text(changeLabel(change)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .font(.system(size: 12))
                }
                if info.changeCount > info.changes.count {
                    Text(L("menubar.update.details.more", info.changeCount - info.changes.count))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text(L("menubar.update.details.explain"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("menubar.update.later")) { close() }
                    .buttonStyle(SecondaryButtonStyle())
                    .tip(L("menubar.update.later.tip"))
                Button(L("menubar.update.now")) {
                    close()
                    updater.update()
                }
                .buttonStyle(AccentButtonStyle())
                .tip(L("menubar.update.now.tip", AppInfo.name))
            }
        }
        .padding(16)
        .frame(width: 320)
    }

}

/// Top-right corner of the menu panel: appears when GitHub has a newer release.
/// It sits in the header so the panel keeps its height.
struct UpdateBadge: View {
    @State private var updater = Updater.shared
    @State private var showsDetails = false
    /// Draws the list of changes in place of the badge, for snapshots (the popover is not drawn there).
    var detailsOnly = false

    var body: some View {
        switch updater.state {
        case .available(let info) where detailsOnly:
            UpdateDetails(info: info) {}
        case .available(let info):
            Button {
                showsDetails = true
            } label: {
                Label(L("menubar.update.badge", info.version), systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(Theme.accentText)
                    .background(Theme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .tip(L("menubar.update.badge.tip", info.version, updater.version))
            .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                UpdateDetails(info: info) { showsDetails = false }
            }
        case .updating:
            HStack(spacing: 6) {
                ProgressView(value: Double(updater.progress.percent), total: 100)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .frame(width: 44)
                Text(updater.progressText).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.textSecondary)
            }
            .tip(L("menubar.update.updating.tip", updater.progressStepText))
        case .failed(let message):
            Button {
                showsDetails = true
            } label: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("menubar.update.failed.accessibility"))
            .tip(message)
            .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                failure(message)
            }
        default:
            EmptyView()
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("menubar.update.failed.title")).font(.system(size: 13, weight: .bold))
            Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("menubar.update.showLog")) { updater.showLog() }
                    .buttonStyle(SecondaryButtonStyle())
                    .tip(L("menubar.update.showLog.tip"))
                Spacer()
                Button(L("menubar.update.checkAgain")) {
                    showsDetails = false
                    Task { await updater.check(userInitiated: true) }
                }
                .buttonStyle(AccentButtonStyle())
                .tip(L("menubar.update.checkAgain.tip"))
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
    @State private var showsChanges = false

    var body: some View {
        Section(L("menubar.updateSettings.title")) {
            HStack {
                Text(L("menubar.updateSettings.version"))
                Spacer()
                Text(updater.versionText).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
            }
            HStack {
                Text(L("menubar.updateSettings.whatsNew"))
                Spacer()
                Button(L("menubar.updateSettings.whatsNew.show")) { WhatsNewTracker.openLatest() }
                    .accessibilityLabel(L("menubar.updateSettings.whatsNew.show.accessibility"))
                    .tip(L("menubar.updateSettings.whatsNew.show.tip"))
            }
            if updater.canCheck {
                Toggle(L("menubar.updateSettings.autoCheck"), isOn: $settings.checkForUpdates)
                    .tip(L("menubar.updateSettings.autoCheck.tip", AppInfo.name))
                HStack {
                    Text(statusText).font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if updater.state == .updating {
                        ProgressView(value: Double(updater.progress.percent), total: 100)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                    } else if case .available(let info) = updater.state {
                        Button(L("menubar.updateSettings.changes")) { showsChanges = true }
                            .fixedSize()
                            .tip(L("menubar.updateSettings.changes.tip"))
                            .popover(isPresented: $showsChanges, arrowEdge: .bottom) {
                                UpdateDetails(info: info) { showsChanges = false }
                            }
                        Button(L("menubar.update.badge", info.version)) { updater.update() }
                            .buttonStyle(AccentButtonStyle())
                            .fixedSize()
                            .tip(L("menubar.update.now.tip", AppInfo.name))
                    } else {
                        Button(L("menubar.updateSettings.checkNow")) { Task { await updater.check(userInitiated: true) } }
                            .disabled(updater.state == .checking)
                            .tip(L("menubar.updateSettings.checkNow.tip"))
                    }
                }
            } else {
                Text(L("menubar.updateSettings.unavailable"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .onChange(of: settings.checkForUpdates) { updater.start() }
    }

    private var statusText: String {
        switch updater.state {
        case .checking: return L("menubar.updateSettings.status.checking")
        case .upToDate: return L("menubar.updateSettings.status.upToDate")
        case .available(let info): return L("menubar.updateSettings.status.available", info.changeCount)
        case .updating: return updater.progressStepText
        case .failed(let message): return message
        case .idle:
            if let checked = updater.lastChecked {
                return L("menubar.updateSettings.status.lastChecked", checked.formatted(date: .omitted, time: .shortened))
            }
            return L("menubar.updateSettings.status.idle")
        }
    }
}
