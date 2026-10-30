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
        home homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
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
                if name == "Library" && (parentPath == home || parentPath == rootPath) {
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
                if isTrackedByGit(url) {
                    continue
                }
                let marker = kind.markerFile(for: url)
                let projectRoot = projectRoot(of: url, within: root)
                let changed = lastChanged(of: projectRoot, kinds: kinds)
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

    /// True when the folder is ~/Library or inside it, as written or once links are resolved.
    public static func isInLibrary(_ folder: URL, home: URL) -> Bool {
        let homePaths = [home.standardizedFileURL.path, home.resolvingSymlinksInPath().path]
        let folderPaths = [folder.standardizedFileURL.path, folder.resolvingSymlinksInPath().path]
        for homePath in homePaths {
            let library = homePath + "/Library"
            for folderPath in folderPaths {
                if folderPath == library || folderPath.hasPrefix(library + "/") {
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

    /// The newest of .git/index, .git/HEAD and the files up to 3 levels below the project folder.
    /// Dependency folders and .git are not entered, so installing packages does not make a project look used.
    public static func lastChanged(of projectRoot: URL, kinds: Set<DependencyKind>) -> Date {
        var newest = Date.distantPast
        for name in ["index", "HEAD"] {
            let file = projectRoot.appendingPathComponent(".git").appendingPathComponent(name)
            if let date = modificationDate(of: file), date > newest {
                newest = date
            }
        }

        var skippedNames: Set<String> = [".git", "Library"]
        for kind in DependencyKind.allCases {
            for folderName in kind.folderNames {
                skippedNames.insert(folderName)
            }
        }
        newest = max(newest, newestFile(in: projectRoot, levelsLeft: 3, skippedNames: skippedNames))
        return newest
    }

    private static func newestFile(in directory: URL, levelsLeft: Int, skippedNames: Set<String>) -> Date {
        var newest = Date.distantPast
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isDirectoryKey, .contentModificationDateKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: []) else {
            return newest
        }
        for item in items {
            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true {
                continue
            }
            if values?.isDirectory == true {
                if skippedNames.contains(item.lastPathComponent) || levelsLeft <= 1 {
                    continue
                }
                let inside = newestFile(in: item, levelsLeft: levelsLeft - 1, skippedNames: skippedNames)
                if inside > newest {
                    newest = inside
                }
                continue
            }
            if let date = values?.contentModificationDate, date > newest {
                newest = date
            }
        }
        return newest
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
