import Foundation

/// Which crashes get a clip: only apps the person worked with recently, never Bugbear itself, and
/// one clip per app in a short window so a crash loop does not flood the history.
public struct CrashClipFilter {
    /// An app counts as "worked with" if it was in front this recently.
    public static let recentSeconds: Double = 600
    /// One clip per app in this window.
    public static let repeatSeconds: Double = 30

    public enum Decision: Equatable {
        case clip
        case ownApp
        case notUsedRecently
        case repeated
    }

    public struct UsedApp: Equatable {
        public var name: String
        public var bundleId: String
        public var time: Double
    }

    /// Automation: accept crashes from any app.
    public var acceptsAnyApp = false
    public let ownName: String
    public private(set) var recentApps: [UsedApp] = []
    private var lastClipTimes: [String: Double] = [:]

    public init(ownName: String) {
        self.ownName = ownName
    }

    public mutating func appActivated(name: String, bundleId: String, at time: Double) {
        recentApps.removeAll { entry in entry.bundleId == bundleId && entry.name == name }
        recentApps.append(UsedApp(name: name, bundleId: bundleId, time: time))
        recentApps.removeAll { entry in time - entry.time > CrashClipFilter.recentSeconds }
    }

    /// Decides for a new crash report; a `.clip` also starts the repeat window for that app.
    /// `frontApp` is the app in front right now, which counts even if it was activated before
    /// Bugbear started watching.
    public mutating func decide(_ report: CrashReport, frontApp: (name: String, bundleId: String)?, now: Double) -> Decision {
        if !acceptsAnyApp {
            if report.appName == ownName {
                return .ownApp
            }
            if !wasUsedRecently(report, frontApp: frontApp, now: now) {
                return .notUsedRecently
            }
        }
        if let last = lastClipTimes[report.appName], now - last < CrashClipFilter.repeatSeconds {
            return .repeated
        }
        lastClipTimes[report.appName] = now
        return .clip
    }

    private func wasUsedRecently(_ report: CrashReport, frontApp: (name: String, bundleId: String)?, now: Double) -> Bool {
        for entry in recentApps where now - entry.time <= CrashClipFilter.recentSeconds {
            if report.belongs(toAppNamed: entry.name, bundleId: entry.bundleId) {
                return true
            }
        }
        if let front = frontApp {
            return report.belongs(toAppNamed: front.name, bundleId: front.bundleId)
        }
        return false
    }
}
