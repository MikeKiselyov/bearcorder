import AppKit
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

    /// How a category is split into rows.
    enum ItemMode {
        /// One row per direct child of each folder (one per app, per Xcode version, per model).
        case perChild
        /// One row for the folder's contents, such as ~/.npm/_cacache.
        case wholeFolder
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
    let itemMode: ItemMode
    /// Run instead of removing files (Go keeps its module cache read-only: `go clean -modcache`).
    let cleanCommand: [String]?
    /// Rows of its review list start ticked. Maven's do not: ~/.m2/repository also holds artifacts
    /// installed with `mvn install`, which may not be downloadable again.
    var startsTicked = true

    /// Developer caches that live inside ~/Library/Caches get their own rows, so "App caches" skips them.
    private static let developerCaches = ["Library/Caches/Yarn", "Library/Caches/Homebrew", "Library/Caches/CocoaPods", "Library/Caches/pip", "Library/Caches/ms-playwright"]

    static let all: [CleanupCategory] = [
        CleanupCategory(id: "appCaches", title: L("space.category.appCaches.title"), detail: L("space.category.appCaches.detail"), symbol: "shippingbox", folders: ["Library/Caches"], keep: developerCaches, action: .deleteContents, itemMode: .perChild, cleanCommand: nil),
        CleanupCategory(id: "derivedData", title: L("space.category.derivedData.title"), detail: L("space.category.derivedData.detail"), symbol: "hammer", folders: ["Library/Developer/Xcode/DerivedData"], keep: [], action: .deleteContents, itemMode: .perChild, cleanCommand: nil),
        CleanupCategory(id: "deviceSupport", title: L("space.category.deviceSupport.title"), detail: L("space.category.deviceSupport.detail"), symbol: "iphone", folders: ["Library/Developer/Xcode/iOS DeviceSupport", "Library/Developer/Xcode/watchOS DeviceSupport", "Library/Developer/Xcode/tvOS DeviceSupport"], keep: [], action: .deleteContents, itemMode: .perChild, cleanCommand: nil),
        CleanupCategory(id: "simulatorCaches", title: L("space.category.simulatorCaches.title"), detail: L("space.category.simulatorCaches.detail"), symbol: "ipad.and.iphone", folders: ["Library/Developer/CoreSimulator/Caches"], keep: [], action: .deleteContents, itemMode: .perChild, cleanCommand: nil),
        CleanupCategory(id: "javascript", title: L("space.category.javascript.title"), detail: L("space.category.javascript.detail"), symbol: "curlybraces", folders: [".npm/_cacache", "Library/Caches/Yarn", "Library/pnpm/store"], keep: [], action: .deleteContents, itemMode: .wholeFolder, cleanCommand: nil),
        CleanupCategory(id: "gradle", title: L("space.category.gradle.title"), detail: L("space.category.gradle.detail"), symbol: "cube", folders: [".gradle/caches"], keep: [], action: .deleteContents, itemMode: .perChild, cleanCommand: nil),
        CleanupCategory(id: "homebrew", title: L("space.category.homebrew.title"), detail: L("space.category.homebrew.detail"), symbol: "mug", folders: ["Library/Caches/Homebrew"], keep: [], action: .deleteContents, itemMode: .wholeFolder, cleanCommand: nil),
        CleanupCategory(id: "cocoapods", title: L("space.category.cocoapods.title"), detail: L("space.category.cocoapods.detail"), symbol: "leaf", folders: ["Library/Caches/CocoaPods"], keep: [], action: .deleteContents, itemMode: .wholeFolder, cleanCommand: nil),
        CleanupCategory(id: "pip", title: L("space.category.pip.title"), detail: L("space.category.pip.detail"), symbol: "chevron.left.forwardslash.chevron.right", folders: ["Library/Caches/pip", ".cache/pip"], keep: [], action: .deleteContents, itemMode: .wholeFolder, cleanCommand: nil),
        CleanupCategory(id: "uv", title: L("space.category.uv.title"), detail: L("space.category.uv.detail"), symbol: "shippingbox", folders: [".cache/uv"], keep: [], action: .deleteContents, itemMode: .wholeFolder, cleanCommand: nil),
        CleanupCategory(id: "bun", title: L("space.category.bun.title"), detail: L("space.category.bun.detail"), symbol: "shippingbox", folders: [".bun/install/cache"], keep: [], action: .deleteContents, itemMode: .wholeFolder, cleanCommand: nil),
        CleanupCategory(id: "goModules", title: L("space.category.goModules.title"), detail: L("space.category.goModules.detail"), symbol: "shippingbox", folders: ["go/pkg/mod"], keep: [], action: .deleteContents, itemMode: .wholeFolder, cleanCommand: ["go", "clean", "-modcache"]),
        CleanupCategory(id: "maven", title: L("space.category.maven.title"), detail: L("space.category.maven.detail"), symbol: "cube", folders: [".m2/repository"], keep: [], action: .deleteContents, itemMode: .perChild, cleanCommand: nil, startsTicked: false),
        CleanupCategory(id: "huggingFace", title: L("space.category.huggingFace.title"), detail: L("space.category.huggingFace.detail"), symbol: "brain", folders: [".cache/huggingface/hub", ".cache/huggingface/datasets"], keep: [], action: .deleteContents, itemMode: .perChild, cleanCommand: nil),
        CleanupCategory(id: "preCommit", title: L("space.category.preCommit.title"), detail: L("space.category.preCommit.detail"), symbol: "checkmark.seal", folders: [".cache/pre-commit"], keep: [], action: .deleteContents, itemMode: .perChild, cleanCommand: nil),
        CleanupCategory(id: "editorCaches", title: L("space.category.editorCaches.title"), detail: L("space.category.editorCaches.detail"), symbol: "curlybraces.square", folders: ["Library/Application Support/Cursor/CachedData", "Library/Application Support/Cursor/Cache", "Library/Application Support/Cursor/CachedExtensionVSIXs", "Library/Application Support/Code/CachedData", "Library/Application Support/Code/Cache", "Library/Application Support/Code/CachedExtensionVSIXs"], keep: [], action: .deleteContents, itemMode: .perChild, cleanCommand: nil),
        CleanupCategory(id: "playwright", title: L("space.category.playwright.title"), detail: L("space.category.playwright.detail"), symbol: "theatermasks", folders: ["Library/Caches/ms-playwright"], keep: [], action: .deleteContents, itemMode: .perChild, cleanCommand: nil),
        CleanupCategory(id: "logs", title: L("space.category.logs.title"), detail: L("space.category.logs.detail", AppInfo.name), symbol: "doc.text", folders: ["Library/Logs"], keep: ["Library/Logs/\(AppInfo.storageName)", "Library/Logs/DiagnosticReports"], action: .deleteContents, itemMode: .perChild, cleanCommand: nil),
        CleanupCategory(id: "captures", title: L("space.category.captures.title", AppInfo.name), detail: L("space.category.captures.detail"), symbol: "photo.on.rectangle", folders: ["Library/Application Support/\(AppInfo.storageName)/Captures"], keep: [], action: .openCaptures, itemMode: .wholeFolder, cleanCommand: nil),
    ]

    /// The name shown for an item: the app's name when the folder is named after an installed app's
    /// bundle id (~/Library/Caches/com.example.App), else the folder's own name.
    static func itemName(for url: URL) -> String {
        let folderName = url.lastPathComponent
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: folderName) {
            return FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
        }
        return folderName
    }
}
