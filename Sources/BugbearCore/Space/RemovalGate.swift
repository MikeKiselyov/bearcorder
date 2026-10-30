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
    case trashedByBugbear(trashed: Set<String>)
}

/// Why the gate refused a removal.
public enum RemovalRefusal: Equatable, Sendable {
    case outsideHome
    case homeOrTopFolder
    case throughLink
    case notAllowedName
    case notInDeclaredCache
    case notTrashedByBugbear
    case missing
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

        if let refusal = targetRefusal(path: path, target: target) {
            return refusal
        }

        if !FileManager.default.fileExists(atPath: path) {
            return .missing
        }
        return nil
    }

    private static func targetRefusal(path: String, target: RemovalTarget) -> RemovalRefusal? {
        switch target {
        case .projectFolder(let kind):
            let name = URL(fileURLWithPath: path).lastPathComponent
            if !kind.folderNames.contains(name) {
                return .notAllowedName
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
        case .trashedByBugbear(let trashed):
            if trashed.contains(path) {
                return nil
            }
            return .notTrashedByBugbear
        }
    }
}
