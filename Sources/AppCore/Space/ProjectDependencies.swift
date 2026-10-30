import Foundation

extension DependencyKind {
    /// The file that proves a folder with this kind's name is a real dependency folder, if there is one.
    func markerFile(for folder: URL) -> URL? {
        let project = folder.deletingLastPathComponent()
        switch self {
        case .nodeModules:
            return existing(["package.json"], in: project)
        case .pythonVenv:
            return existing(["pyvenv.cfg"], in: folder)
        case .pods:
            return existing(["Podfile"], in: project)
        case .cargoTarget:
            return existing(["Cargo.toml"], in: project)
        case .swiftBuild:
            return existing(["Package.swift"], in: project)
        case .gradleBuild:
            return existing(["build.gradle", "build.gradle.kts"], in: project)
        case .gradleCache:
            return existing(["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"], in: project)
        }
    }

    /// True when the marker of this kind is where it should be.
    public func isProven(_ folder: URL) -> Bool {
        return markerFile(for: folder) != nil
    }

    private func existing(_ names: [String], in directory: URL) -> URL? {
        for name in names {
            let candidate = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

/// A dependency folder found inside a project.
public struct ProjectDependency: Equatable, Sendable {
    public var url: URL
    public var kind: DependencyKind
    public var projectRoot: URL
    public var bytes: Int64
    /// When the whole project last changed, not the dependency folder.
    public var lastChanged: Date
    public var snapshot: FolderSnapshot

    public init(url: URL, kind: DependencyKind, projectRoot: URL, bytes: Int64, lastChanged: Date, snapshot: FolderSnapshot) {
        self.url = url
        self.kind = kind
        self.projectRoot = projectRoot
        self.bytes = bytes
        self.lastChanged = lastChanged
        self.snapshot = snapshot
    }
}

public struct ProjectScanResult: Sendable {
    public var found: [ProjectDependency]
    public var unreadableRoots: [URL]

    public init(found: [ProjectDependency], unreadableRoots: [URL]) {
        self.found = found
        self.unreadableRoots = unreadableRoots
    }
}

/// When each project last changed, read once per project folder: a monorepo with many dependency
/// folders is read once, not once per folder. Lives for one scan or one removal.
public final class ProjectAges {
    /// How many times a project was actually read (tests).
    public private(set) var reads = 0
    private let entryLimit: Int
    private var dates: [String: Date] = [:]

    public init(entryLimit: Int = 50_000) {
        self.entryLimit = entryLimit
    }

    public func lastChanged(of projectRoot: URL, kinds: Set<DependencyKind>) -> Date {
        let key = projectRoot.standardizedFileURL.path
        if let known = dates[key] {
            return known
        }
        reads += 1
        let date = ProjectDependencies.lastChanged(of: projectRoot, kinds: kinds, entryLimit: entryLimit)
        dates[key] = date
        return date
    }
}

/// Finds dependency folders inside the person's project folders, measures them and dates their projects.
public enum ProjectDependencies {
    /// A root in `home`'s Library (app data, iCloud Drive, cloud storage), also through a link,
    /// is never searched: it is reported with the unreadable roots.
    public static func scan(
        roots: [URL],
        kinds: Set<DependencyKind>,
        maxDepth: Int,
        isTrackedByGit: (URL) -> Bool,
        shouldStop: () -> Bool,
        home homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        ages: ProjectAges = ProjectAges()
    ) -> ProjectScanResult {
        var found: [ProjectDependency] = []
        var unreadableRoots: [URL] = []
        let home = homeURL.standardizedFileURL.path

        for root in roots {
            if shouldStop() {
                break
            }
            if isInLibrary(root, home: homeURL) {
                unreadableRoots.append(root)
                continue
            }
            guard (try? FileManager.default.contentsOfDirectory(atPath: root.path)) != nil else {
                unreadableRoots.append(root)
                continue
            }
            let rootPath = root.standardizedFileURL.path
            let rootDevice = device(of: root)
            let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey]
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else {
                unreadableRoots.append(root)
                continue
            }

            for case let url as URL in walker {
                if shouldStop() {
                    break
                }
                let values = try? url.resourceValues(forKeys: Set(keys))
                // The walk never goes into a link. skipDescendants() is only for folders: called on a
                // link it makes the walk skip the folder that comes after it.
                if values?.isSymbolicLink == true {
                    continue
                }
                if values?.isDirectory != true {
                    continue
                }
                if walker.level > maxDepth {
                    walker.skipDescendants()
                    continue
                }

                let name = url.lastPathComponent
                let parentPath = url.deletingLastPathComponent().standardizedFileURL.path
                if name == ".git" {
                    walker.skipDescendants()
                    continue
                }
                if name.lowercased() == "library" && (parentPath == home || parentPath == rootPath) {
                    walker.skipDescendants()
                    continue
                }
                if let rootDevice = rootDevice, let folderDevice = device(of: url), folderDevice != rootDevice {
                    walker.skipDescendants()
                    continue
                }

                guard let kind = provenKind(of: url, kinds: kinds) else {
                    continue
                }
                // Whatever happens next, what is inside a dependency folder is not looked at.
                walker.skipDescendants()
                // A clone or a worktree that only has a dependency folder's name.
                if hasOwnRepository(url) {
                    continue
                }
                if isTrackedByGit(url) {
                    continue
                }
                let marker = kind.markerFile(for: url)
                let projectRoot = projectRoot(of: url, within: root)
                let changed = ages.lastChanged(of: projectRoot, kinds: kinds)
                guard let snapshot = FolderSnapshot.take(of: url, marker: marker, projectRoot: projectRoot, projectChanged: changed) else {
                    continue
                }
                found.append(ProjectDependency(
                    url: url,
                    kind: kind,
                    projectRoot: projectRoot,
                    bytes: FileSizes.folder(url),
                    lastChanged: changed,
                    snapshot: snapshot
                ))
            }
        }
        return ProjectScanResult(found: found, unreadableRoots: unreadableRoots)
    }

    /// True when the folder is ~/Library or inside it, as written or once links are resolved, in
    /// any case (~/library is the same folder on a case-insensitive disk).
    public static func isInLibrary(_ folder: URL, home: URL) -> Bool {
        let homePaths = [home.standardizedFileURL.path, home.resolvingSymlinksInPath().path]
        let folderPaths = [folder.standardizedFileURL.path, folder.resolvingSymlinksInPath().path]
        for homePath in homePaths {
            let library = (homePath + "/Library").lowercased()
            for folderPath in folderPaths {
                let lowercased = folderPath.lowercased()
                if lowercased == library || lowercased.hasPrefix(library + "/") {
                    return true
                }
            }
        }
        return false
    }

    /// The nearest folder above with a .git that is the scan root or below it, else the folder's parent.
    /// A repository above the scan root (such as dotfiles in the home folder) is not a project here.
    public static func projectRoot(of folder: URL, within scanRoot: URL) -> URL {
        let parent = folder.deletingLastPathComponent()
        let scanRootPath = scanRoot.standardizedFileURL.path
        var candidate = parent
        while true {
            let candidatePath = candidate.standardizedFileURL.path
            if candidatePath != scanRootPath && !candidatePath.hasPrefix(scanRootPath + "/") {
                break
            }
            let git = candidate.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: git.path) {
                return candidate
            }
            if candidatePath == scanRootPath {
                break
            }
            let above = candidate.deletingLastPathComponent()
            if above.path == candidate.path {
                break
            }
            candidate = above
        }
        return parent
    }

    /// True when the folder has a .git of its own (a folder, or a file for a worktree or submodule).
    public static func hasOwnRepository(_ folder: URL) -> Bool {
        var info = stat()
        return lstat(folder.appendingPathComponent(".git").path, &info) == 0
    }

    /// How deep `lastChanged` reads below the project folder: deep enough for src/main/java/com/x/y.
    static let ageDepth = 12

    /// The newest of .git/index, .git/HEAD and the files up to `ageDepth` levels below the project
    /// folder. .git and proven dependency folders are not entered, so installing packages does not
    /// make a project look used; a folder that only has such a name (a Java package called build) is.
    /// A project with more than `entryLimit` files and folders has no known age: `Date.distantPast`,
    /// so it is never ticked on its own.
    public static func lastChanged(of projectRoot: URL, kinds: Set<DependencyKind>, entryLimit: Int = 50_000) -> Date {
        var newest = Date.distantPast
        for name in ["index", "HEAD"] {
            let file = projectRoot.appendingPathComponent(".git").appendingPathComponent(name)
            if let date = modificationDate(of: file), date > newest {
                newest = date
            }
        }
        var entriesLeft = entryLimit
        let files = newestFile(in: projectRoot, levelsLeft: ageDepth, entriesLeft: &entriesLeft)
        if entriesLeft < 0 {
            return Date.distantPast
        }
        return max(newest, files)
    }

    private static func newestFile(in directory: URL, levelsLeft: Int, entriesLeft: inout Int) -> Date {
        var newest = Date.distantPast
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey, .contentModificationDateKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: []) else {
            return newest
        }
        for item in items {
            entriesLeft -= 1
            if entriesLeft < 0 {
                return newest
            }
            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true {
                continue
            }
            if values?.isDirectory == true {
                if levelsLeft <= 1 || isSkippedForAge(item, atProjectTop: levelsLeft == ageDepth) {
                    continue
                }
                let inside = newestFile(in: item, levelsLeft: levelsLeft - 1, entriesLeft: &entriesLeft)
                if inside > newest {
                    newest = inside
                }
                if entriesLeft < 0 {
                    return newest
                }
                continue
            }
            if let date = values?.contentModificationDate, date > newest {
                newest = date
            }
        }
        return newest
    }

    /// .git, the project's own top-level Library (any case) and the dependency folders proven by
    /// their marker. Every kind counts here, also ones turned off in the settings: their folders are
    /// installed, not edited.
    private static func isSkippedForAge(_ folder: URL, atProjectTop: Bool) -> Bool {
        let name = folder.lastPathComponent
        if name == ".git" {
            return true
        }
        if atProjectTop && name.lowercased() == "library" {
            return true
        }
        for kind in DependencyKind.allCases {
            if kind.folderNames.contains(name) && kind.isProven(folder) {
                return true
            }
        }
        return false
    }

    private static func provenKind(of folder: URL, kinds: Set<DependencyKind>) -> DependencyKind? {
        let name = folder.lastPathComponent
        for kind in DependencyKind.allCases {
            if kinds.contains(kind) && kind.folderNames.contains(name) && kind.isProven(folder) {
                return kind
            }
        }
        return nil
    }

    private static func modificationDate(of file: URL) -> Date? {
        let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    private static func device(of url: URL) -> dev_t? {
        var info = stat()
        if lstat(url.path, &info) != 0 {
            return nil
        }
        return info.st_dev
    }
}
