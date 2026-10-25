import AppKit
import BugbearCore
import SwiftUI

/// Decides on launch whether to show "What's new", and remembers what was shown.
@MainActor
enum WhatsNewTracker {
    static let lastSeenKey = "whatsNewLastSeenID"
    /// Set by Updater right before it rebuilds the app; read and cleared on the next launch.
    static let updatedFromKey = "updatedFromCommit"

    /// New users get the welcome guide instead; everything that exists now counts as seen.
    static func markAllSeen() {
        UserDefaults.standard.set(WhatsNew.latestID(WhatsNewCatalog.releases), forKey: lastSeenKey)
    }

    static func checkOnLaunch() {
        let defaults = UserDefaults.standard
        let updatedFrom = defaults.string(forKey: updatedFromKey) ?? ""
        defaults.removeObject(forKey: updatedFromKey)
        let unseen = WhatsNew.unseen(WhatsNewCatalog.releases, lastSeenID: defaults.integer(forKey: lastSeenKey))
        let updater = Updater.shared
        Task {
            var changes: [String] = []
            if !updatedFrom.isEmpty && updatedFrom != updater.commit {
                changes = await commitTitles(from: updatedFrom, to: updater.commit, in: updater.sourcePath)
            }
            guard WhatsNew.shouldShow(unseenReleases: unseen, updatedFromCommit: updatedFrom, changes: changes) else { return }
            Log.info("what's new: \(unseen.count) releases, \(changes.count) changes")
            open(releases: unseen, changes: changes)
            markAllSeen()
        }
    }

    static func open(releases: [WhatsNewRelease], changes: [String]) {
        WindowManager.shared.show(id: "whats-new", title: "What's new", size: CGSize(width: 720, height: 640), minSize: CGSize(width: 620, height: 480)) {
            WhatsNewView(releases: releases, changes: changes)
        }
    }

    /// Settings → "What's new": the latest notes again.
    static func openLatest() {
        var latest: [WhatsNewRelease] = []
        if let newest = WhatsNew.unseen(WhatsNewCatalog.releases, lastSeenID: 0).first {
            latest.append(newest)
        }
        open(releases: latest, changes: [])
    }

    /// First lines of the commits between two builds, newest first, from the local clone.
    static func commitTitles(from oldCommit: String, to newCommit: String, in folder: String) async -> [String] {
        if folder.isEmpty || newCommit.isEmpty { return [] }
        let task = Task.detached(priority: .utility) { () -> [String] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", folder, "log", "--no-merges", "--format=%s", "-n", "40", "\(oldCommit)..\(newCommit)"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return []
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus != 0 { return [] }
            var titles: [String] = []
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                titles.append(String(line))
            }
            return titles
        }
        return await task.value
    }
}

struct WhatsNewView: View {
    var releases: [WhatsNewRelease]
    var changes: [String]

    private let columns = [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    ForEach(releases, id: \.id) { release in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(release.version)
                                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .foregroundStyle(Theme.accentText)
                                    .background(Theme.accent)
                                    .clipShape(Capsule())
                                Text(release.title).font(.system(size: 15, weight: .semibold))
                            }
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(Array(release.items.enumerated()), id: \.offset) { _, item in
                                    card(item)
                                }
                            }
                        }
                    }
                    if !changes.isEmpty {
                        changeList
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 44)
                .padding(.bottom, 24)
            }
            HStack {
                Text("Reopen this from Settings → Updates.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Got it") { WindowManager.shared.close(id: "whats-new") }
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .tip("Close this window (Return)")
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(Theme.sidebar)
        }
        .foregroundStyle(Theme.text)
        .background(Theme.window)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: Logo.menuBarImage(recording: false))
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 47)
                .foregroundStyle(Theme.text)
            VStack(alignment: .leading, spacing: 4) {
                Text("What's new in Bugbear").font(.system(size: 24, weight: .bold))
                Text("Version \(Updater.shared.versionText)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func card(_ item: WhatsNewRelease.Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.accentSoft)
                    .frame(width: 22)
                Text(item.title).font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
            }
            Text(item.text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !item.shortcut.isEmpty {
                Text(item.shortcut)
                    .font(.system(size: 11, weight: .semibold, design: item.shortcut.hasPrefix("⌥") ? .monospaced : .default))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.control)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.borderStrong, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var changeList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("All changes since your last version")
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Theme.textSecondary)
                        Text(change).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 12))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
