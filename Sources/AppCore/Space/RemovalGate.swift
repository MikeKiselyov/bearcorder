import Foundation

/// The kinds of dependency and build folders Space can find inside projects.
public enum DependencyKind: String, CaseIterable, Sendable {
    case nodeModules, pythonVenv, pods, cargoTarget, swiftBuild, gradleBuild, gradleCache

    /// The folder names this kind may be removed under.
    public var folderNames: [String] {
        switch self {
        case .nodeModules: return ["node_modules"]
        case .pythonVenv: return [".venv", "venv"]
        case .pods: return ["Pods"]
        case .cargoTarget: return ["target"]
        case .swiftBuild: return [".build"]
        case .gradleBuild: return ["build"]
        case .gradleCache: return [".gradle"]
        }
    }
}

/// What a removal is meant to delete; the gate checks the folder against it.
public enum RemovalTarget {
    case projectFolder(DependencyKind)
    case cacheItem(allowedRoots: [URL])
    case trashedByApp(trashed: Set<String>)
}

/// Why the gate refused a removal.
public enum RemovalRefusal: Equatable, Sendable {
    case outsideHome
    case homeOrTopFolder
    case throughLink
    case notAllowedName
    case notInDeclaredCache
    case notTrashedByApp
    case missing
    /// A project folder that is a repository of its own (its own .git): a clone or a worktree.
    case ownRepository
    /// A project folder in ~/Library (app data, iCloud Drive, cloud storage).
    case inLibrary
}

/// Every removal passes through here. nil means the folder may be removed.
public enum RemovalGate {
    public static func refusal(for url: URL, target: RemovalTarget, home: URL) -> RemovalRefusal? {
        // ".." is resolved first, so a path cannot climb out of where it seems to be.
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path

        let homePrefix = homePath + "/"
        if !path.hasPrefix(homePrefix) && path != homePath {
            return .outsideHome
        }

        // The home folder and the folders right under it (Documents, Projects) are never removed.
        let relativePath = String(path.dropFirst(homePath.count))
        let relativeComponents = relativePath.split(separator: "/")
        if relativeComponents.count <= 1 {
            return .homeOrTopFolder
        }

        // Walk from home down. A link anywhere on the way (the folder itself included) is refused.
        var current = URL(fileURLWithPath: homePath)
        for component in relativeComponents {
            current = current.appendingPathComponent(String(component))
            let values = try? current.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                return .throughLink
            }
        }

        if let refusal = targetRefusal(path: path, target: target, home: home) {
            return refusal
        }

        if !FileManager.default.fileExists(atPath: path) {
            return .missing
        }
        return nil
    }

    /// The path with every link resolved; nil when it cannot be resolved (gone, unreadable).
    /// Taken when the gate passes and again right before removing: a folder on the way swapped
    /// for a link in between makes the two differ.
    public static func realPath(of url: URL) -> String? {
        guard let resolved = realpath(url.path, nil) else {
            return nil
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// The real path to record as checked, once the gate has passed: only when it is the home's
    /// real path plus the path below the home, so a folder swapped for a link between the gate and
    /// this call is not recorded as checked. nil otherwise (the removal is then refused).
    public static func checkedRealPath(of url: URL, home: URL) -> String? {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        if !path.hasPrefix(homePath + "/") {
            return nil
        }
        let relative = String(path.dropFirst(homePath.count))
        guard let homeReal = realPath(of: home), let real = realPath(of: url) else {
            return nil
        }
        if real != homeReal + relative {
            return nil
        }
        return real
    }

    /// True when the path still resolves to the one taken when the gate passed.
    public static func stillLeads(_ url: URL, to checkedPath: String?) -> Bool {
        guard let checkedPath = checkedPath, let now = realPath(of: url) else {
            return false
        }
        return now == checkedPath
    }

    private static func targetRefusal(path: String, target: RemovalTarget, home: URL) -> RemovalRefusal? {
        switch target {
        case .projectFolder(let kind):
            let folder = URL(fileURLWithPath: path)
            if !kind.folderNames.contains(folder.lastPathComponent) {
                return .notAllowedName
            }
            if ProjectDependencies.isInLibrary(folder, home: home) {
                return .inLibrary
            }
            if ProjectDependencies.hasOwnRepository(folder) {
                return .ownRepository
            }
            return nil
        case .cacheItem(let allowedRoots):
            for root in allowedRoots {
                let rootPrefix = root.standardizedFileURL.path + "/"
                if path.hasPrefix(rootPrefix) {
                    return nil
                }
            }
            return .notInDeclaredCache
        case .trashedByApp(let trashed):
            if trashed.contains(path) {
                return nil
            }
            return .notTrashedByApp
        }
    }
}
