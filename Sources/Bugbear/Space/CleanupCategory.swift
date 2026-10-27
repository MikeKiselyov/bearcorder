import Foundation
import BugbearCore

/// Something on disk that can be cleaned or looked at: caches apps rebuild, developer leftovers, logs.
struct CleanupCategory: Identifiable {
    enum Action {
        /// The contents are deleted for good: apps and tools create them again when needed.
        case deleteContents
        /// Our own captures: cleaned in Recent or by Settings → Storage, never in one click.
        case openCaptures
    }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    /// Folders below the home folder whose contents are measured and cleaned.
    let folders: [String]
    /// Paths below the home folder left alone and not counted (another category covers them).
    let keep: [String]
    let action: Action

    /// Developer caches that live inside ~/Library/Caches get their own rows, so "App caches" skips them.
    private static let developerCaches = ["Library/Caches/Yarn", "Library/Caches/Homebrew", "Library/Caches/CocoaPods", "Library/Caches/pip"]

    static let all: [CleanupCategory] = [
        CleanupCategory(id: "appCaches", title: "App caches", detail: "Files apps keep to start and load faster. They are made again as needed; apps may be slower for a moment. Apple's own caches are left alone.", symbol: "shippingbox", folders: ["Library/Caches"], keep: developerCaches, action: .deleteContents),
        CleanupCategory(id: "derivedData", title: "Xcode DerivedData", detail: "Build products and indexes. The next build of each project takes longer.", symbol: "hammer", folders: ["Library/Developer/Xcode/DerivedData"], keep: [], action: .deleteContents),
        CleanupCategory(id: "deviceSupport", title: "Xcode device support", detail: "Symbols copied from devices you debugged. Xcode copies them again when a device connects.", symbol: "iphone", folders: ["Library/Developer/Xcode/iOS DeviceSupport", "Library/Developer/Xcode/watchOS DeviceSupport", "Library/Developer/Xcode/tvOS DeviceSupport"], keep: [], action: .deleteContents),
        CleanupCategory(id: "simulatorCaches", title: "Simulator caches", detail: "Cached data of iOS simulators. Simulators and their apps stay.", symbol: "ipad.and.iphone", folders: ["Library/Developer/CoreSimulator/Caches"], keep: [], action: .deleteContents),
        CleanupCategory(id: "javascript", title: "npm, Yarn and pnpm caches", detail: "Downloaded packages. They are downloaded again on the next install.", symbol: "curlybraces", folders: [".npm/_cacache", "Library/Caches/Yarn", "Library/pnpm/store"], keep: [], action: .deleteContents),
        CleanupCategory(id: "gradle", title: "Gradle caches", detail: "Downloaded dependencies and build caches of Android and Java projects.", symbol: "cube", folders: [".gradle/caches"], keep: [], action: .deleteContents),
        CleanupCategory(id: "homebrew", title: "Homebrew downloads", detail: "Installers Homebrew kept after installing. Installed tools stay.", symbol: "mug", folders: ["Library/Caches/Homebrew"], keep: [], action: .deleteContents),
        CleanupCategory(id: "cocoapods", title: "CocoaPods cache", detail: "Downloaded pods. Projects keep their own copies.", symbol: "leaf", folders: ["Library/Caches/CocoaPods"], keep: [], action: .deleteContents),
        CleanupCategory(id: "pip", title: "pip cache", detail: "Downloaded Python packages. Installed packages stay.", symbol: "chevron.left.forwardslash.chevron.right", folders: ["Library/Caches/pip", ".cache/pip"], keep: [], action: .deleteContents),
        CleanupCategory(id: "logs", title: "Logs", detail: "Logs apps wrote for troubleshooting. \(AppInfo.name)'s own log and crash reports stay.", symbol: "doc.text", folders: ["Library/Logs"], keep: ["Library/Logs/\(AppInfo.storageName)", "Library/Logs/DiagnosticReports"], action: .deleteContents),
        CleanupCategory(id: "captures", title: "\(AppInfo.name) captures", detail: "Your screenshots and clips. Delete them in Recent, or set limits in Settings → Storage.", symbol: "photo.on.rectangle", folders: ["Library/Application Support/\(AppInfo.storageName)/Captures"], keep: [], action: .openCaptures),
    ]
}
