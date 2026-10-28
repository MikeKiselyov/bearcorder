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
        CleanupCategory(id: "appCaches", title: L("space.category.appCaches.title"), detail: L("space.category.appCaches.detail"), symbol: "shippingbox", folders: ["Library/Caches"], keep: developerCaches, action: .deleteContents),
        CleanupCategory(id: "derivedData", title: L("space.category.derivedData.title"), detail: L("space.category.derivedData.detail"), symbol: "hammer", folders: ["Library/Developer/Xcode/DerivedData"], keep: [], action: .deleteContents),
        CleanupCategory(id: "deviceSupport", title: L("space.category.deviceSupport.title"), detail: L("space.category.deviceSupport.detail"), symbol: "iphone", folders: ["Library/Developer/Xcode/iOS DeviceSupport", "Library/Developer/Xcode/watchOS DeviceSupport", "Library/Developer/Xcode/tvOS DeviceSupport"], keep: [], action: .deleteContents),
        CleanupCategory(id: "simulatorCaches", title: L("space.category.simulatorCaches.title"), detail: L("space.category.simulatorCaches.detail"), symbol: "ipad.and.iphone", folders: ["Library/Developer/CoreSimulator/Caches"], keep: [], action: .deleteContents),
        CleanupCategory(id: "javascript", title: L("space.category.javascript.title"), detail: L("space.category.javascript.detail"), symbol: "curlybraces", folders: [".npm/_cacache", "Library/Caches/Yarn", "Library/pnpm/store"], keep: [], action: .deleteContents),
        CleanupCategory(id: "gradle", title: L("space.category.gradle.title"), detail: L("space.category.gradle.detail"), symbol: "cube", folders: [".gradle/caches"], keep: [], action: .deleteContents),
        CleanupCategory(id: "homebrew", title: L("space.category.homebrew.title"), detail: L("space.category.homebrew.detail"), symbol: "mug", folders: ["Library/Caches/Homebrew"], keep: [], action: .deleteContents),
        CleanupCategory(id: "cocoapods", title: L("space.category.cocoapods.title"), detail: L("space.category.cocoapods.detail"), symbol: "leaf", folders: ["Library/Caches/CocoaPods"], keep: [], action: .deleteContents),
        CleanupCategory(id: "pip", title: L("space.category.pip.title"), detail: L("space.category.pip.detail"), symbol: "chevron.left.forwardslash.chevron.right", folders: ["Library/Caches/pip", ".cache/pip"], keep: [], action: .deleteContents),
        CleanupCategory(id: "logs", title: L("space.category.logs.title"), detail: L("space.category.logs.detail", AppInfo.name), symbol: "doc.text", folders: ["Library/Logs"], keep: ["Library/Logs/\(AppInfo.storageName)", "Library/Logs/DiagnosticReports"], action: .deleteContents),
        CleanupCategory(id: "captures", title: L("space.category.captures.title", AppInfo.name), detail: L("space.category.captures.detail"), symbol: "photo.on.rectangle", folders: ["Library/Application Support/\(AppInfo.storageName)/Captures"], keep: [], action: .openCaptures),
    ]
}
