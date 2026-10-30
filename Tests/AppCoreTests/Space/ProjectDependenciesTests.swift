import AppCore
import XCTest

/// Space lists a dependency folder only when its name is known and a marker file proves it.
final class ProjectDependenciesTests: XCTestCase {
    var root: URL!
    let fileManager = FileManager.default

    override func setUpWithError() throws {
        let base = fileManager.temporaryDirectory.appendingPathComponent("deps-\(UUID().uuidString)")
        root = base.appendingPathComponent("projects")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try? fileManager.removeItem(at: root.deletingLastPathComponent())
    }

    @discardableResult
    func makeFile(_ relativePath: String, in base: URL? = nil, text: String = "data") throws -> URL {
        let file = (base ?? root).appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func scan(
        roots: [URL]? = nil,
        kinds: Set<DependencyKind> = Set(DependencyKind.allCases),
        maxDepth: Int = 6,
        isTrackedByGit: @escaping (URL) -> Bool = { _ in false },
        shouldStop: @escaping () -> Bool = { false }
    ) -> ProjectScanResult {
        return ProjectDependencies.scan(
            roots: roots ?? [root],
            kinds: kinds,
            maxDepth: maxDepth,
            isTrackedByGit: isTrackedByGit,
            shouldStop: shouldStop
        )
    }

    func relativePaths(_ result: ProjectScanResult) -> [String] {
        let rootPath = root.standardizedFileURL.path + "/"
        var paths: [String] = []
        for dependency in result.found {
            paths.append(String(dependency.url.standardizedFileURL.path.dropFirst(rootPath.count)))
        }
        return paths.sorted()
    }

    func testFindsProvenFolders() throws {
        try makeFile("app/node_modules/lib/index.js")
        try makeFile("app/package.json")
        try makeFile("py/.venv/pyvenv.cfg")
        try makeFile("ios/Pods/Pod.h")
        try makeFile("ios/Podfile")
        try makeFile("rs/target/out.bin")
        try makeFile("rs/Cargo.toml")
        try makeFile("sw/.build/out.o")
        try makeFile("sw/Package.swift")
        try makeFile("gr/build/classes.bin")
        try makeFile("gr/build.gradle.kts")

        let result = scan()
        XCTAssertEqual(relativePaths(result), [
            "app/node_modules", "gr/build", "ios/Pods", "py/.venv", "rs/target", "sw/.build",
        ])
        for dependency in result.found {
            XCTAssertGreaterThan(dependency.bytes, 0, dependency.url.path)
            XCTAssertNotNil(dependency.snapshot.marker)
        }
    }

    func testUnprovenNamesAreIgnored() throws {
        try makeFile("x/build/file.bin")
        try makeFile("y/node_modules/file.js")
        try makeFile("z/venv/file.py")
        XCTAssertEqual(relativePaths(scan()), [])
    }

    func testGradleCacheNeedsAGradleFile() throws {
        try makeFile("a/.gradle/cache.bin")
        try makeFile("b/.gradle/cache.bin")
        try makeFile("b/settings.gradle")
        XCTAssertEqual(relativePaths(scan()), ["b/.gradle"])
    }

    func testNestedDependenciesListedOnce() throws {
        try makeFile("app/package.json")
        try makeFile("app/node_modules/file.js")
        try makeFile("app/node_modules/pkg/package.json")
        try makeFile("app/node_modules/pkg/node_modules/inner.js")
        XCTAssertEqual(relativePaths(scan()), ["app/node_modules"])
    }

    func testLinksAreNotFollowed() throws {
        let otherHome = root.deletingLastPathComponent().appendingPathComponent("other-home")
        try makeFile("app/node_modules/file.js", in: otherHome)
        try makeFile("app/package.json", in: otherHome)
        try fileManager.createSymbolicLink(at: root.appendingPathComponent("home-link"), withDestinationURL: otherHome)

        XCTAssertEqual(relativePaths(scan()), [])
    }

    /// A link next to projects used to make the walk skip the folder listed after it (found by the
    /// e2e "space review": vendored disappeared behind link-home). Many projects, so one comes after
    /// the link whatever order the disk lists them in.
    func testLinkDoesNotHideTheProjectsNextToIt() throws {
        var expected: [String] = []
        for number in 1...12 {
            try makeFile("app\(number)/package.json")
            try makeFile("app\(number)/node_modules/index.js")
            expected.append("app\(number)/node_modules")
        }
        let target = root.deletingLastPathComponent().appendingPathComponent("elsewhere")
        try makeFile("file.txt", in: target)
        for name in ["link-home", "a-link", "m-link", "z-link"] {
            try fileManager.createSymbolicLink(at: root.appendingPathComponent(name), withDestinationURL: target)
        }
        XCTAssertEqual(relativePaths(scan()), expected.sorted())
    }

    func testLinkedDependencyFolderIsNotListed() throws {
        let target = root.deletingLastPathComponent().appendingPathComponent("elsewhere")
        try makeFile("file.js", in: target)
        try makeFile("app/package.json")
        try fileManager.createSymbolicLink(at: root.appendingPathComponent("app/node_modules"), withDestinationURL: target)
        XCTAssertEqual(relativePaths(scan()), [])
    }

    func testTrackedByGitIsSkipped() throws {
        try makeFile("vendored/node_modules/file.js")
        try makeFile("vendored/package.json")
        try makeFile("app/node_modules/file.js")
        try makeFile("app/package.json")

        let result = scan(isTrackedByGit: { folder in
            return folder.path.hasSuffix("vendored/node_modules")
        })
        XCTAssertEqual(relativePaths(result), ["app/node_modules"])
    }

    func testAgeIsTheProjects() throws {
        try makeFile("spok/.git/index")
        try makeFile("spok/.git/HEAD")
        let podfile = try makeFile("spok/ios/Podfile")
        let pods = try makeFile("spok/ios/Pods/Pod.h").deletingLastPathComponent()
        let old = Date().addingTimeInterval(-124 * 24 * 3600)
        try fileManager.setAttributes([.modificationDate: old], ofItemAtPath: podfile.path)
        try fileManager.setAttributes([.modificationDate: old], ofItemAtPath: pods.appendingPathComponent("Pod.h").path)
        try fileManager.setAttributes([.modificationDate: old], ofItemAtPath: pods.path)

        let result = scan()
        XCTAssertEqual(result.found.count, 1)
        let dependency = try XCTUnwrap(result.found.first)
        XCTAssertEqual(dependency.lastChanged.timeIntervalSinceNow, 0, accuracy: 60)
        XCTAssertEqual(dependency.projectRoot.standardizedFileURL.lastPathComponent, "spok")
        XCTAssertEqual(dependency.snapshot.projectChanged, dependency.lastChanged)
    }

    func testProjectRootIsTheNearestRepositoryElseTheParent() throws {
        try makeFile("repo/.git/HEAD")
        let inRepo = try makeFile("repo/packages/web/node_modules/a.js").deletingLastPathComponent()
        let loose = try makeFile("loose/node_modules/a.js").deletingLastPathComponent()
        XCTAssertEqual(ProjectDependencies.projectRoot(of: inRepo, within: root).lastPathComponent, "repo")
        XCTAssertEqual(ProjectDependencies.projectRoot(of: loose, within: root).lastPathComponent, "loose")
    }

    func testRepositoryAboveTheScanRootIsIgnored() throws {
        let outer = root.deletingLastPathComponent()
        let outerIndex = try makeFile(".git/index", in: outer)
        try makeFile("loose/package.json")
        let folder = try makeFile("loose/node_modules/a.js").deletingLastPathComponent()
        let projectFile = root.appendingPathComponent("loose/package.json")
        let old = Date().addingTimeInterval(-90 * 24 * 3600)
        try fileManager.setAttributes([.modificationDate: old], ofItemAtPath: projectFile.path)
        try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: outerIndex.path)

        XCTAssertEqual(ProjectDependencies.projectRoot(of: folder, within: root).lastPathComponent, "loose")
        let result = scan()
        let dependency = try XCTUnwrap(result.found.first)
        XCTAssertEqual(dependency.projectRoot.lastPathComponent, "loose")
        XCTAssertEqual(dependency.lastChanged.timeIntervalSince(old), 0, accuracy: 60)
    }

    func testLastChangedDoesNotEnterLibrary() throws {
        let project = root.appendingPathComponent("proj")
        let projectFile = try makeFile("package.json", in: project)
        let old = Date().addingTimeInterval(-90 * 24 * 3600)
        try fileManager.setAttributes([.modificationDate: old], ofItemAtPath: projectFile.path)
        try makeFile("Library/new.txt", in: project)

        let changed = ProjectDependencies.lastChanged(of: project, kinds: Set(DependencyKind.allCases))
        XCTAssertEqual(changed.timeIntervalSince(old), 0, accuracy: 60)
    }

    func testDepthLimit() throws {
        try makeFile("a/b/c/d/e/f/node_modules/file.js")
        try makeFile("a/b/c/d/e/f/package.json")
        XCTAssertEqual(relativePaths(scan(maxDepth: 6)), [])
        XCTAssertEqual(relativePaths(scan(maxDepth: 7)), ["a/b/c/d/e/f/node_modules"])
    }

    func testUnreadableRootIsReported() throws {
        let locked = root.deletingLastPathComponent().appendingPathComponent("locked")
        try fileManager.createDirectory(at: locked, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        try makeFile("app/node_modules/file.js")
        try makeFile("app/package.json")

        let result = scan(roots: [locked, root])
        XCTAssertEqual(result.unreadableRoots.map { $0.standardizedFileURL.path }, [locked.standardizedFileURL.path])
        XCTAssertEqual(relativePaths(result), ["app/node_modules"])
    }

    func testStopEndsTheScan() throws {
        try makeFile("a/node_modules/file.js")
        try makeFile("a/package.json")
        try makeFile("b/node_modules/file.js")
        try makeFile("b/package.json")
        var checks = 0
        let result = scan(shouldStop: {
            checks += 1
            return checks > 1
        })
        XCTAssertLessThan(result.found.count, 2)
    }

    func testOnlyChosenKinds() throws {
        try makeFile("app/node_modules/file.js")
        try makeFile("app/package.json")
        try makeFile("py/.venv/pyvenv.cfg")
        try makeFile("rs/target/out.bin")
        try makeFile("rs/Cargo.toml")
        XCTAssertEqual(relativePaths(scan(kinds: [.nodeModules])), ["app/node_modules"])
    }

    func testLibraryDirectlyUnderARootIsNotEntered() throws {
        try makeFile("Library/app/node_modules/file.js")
        try makeFile("Library/app/package.json")
        try makeFile("Other/Library/app/node_modules/file.js")
        try makeFile("Other/Library/app/package.json")
        XCTAssertEqual(relativePaths(scan()), ["Other/Library/app/node_modules"])
    }

    /// A root in the home's Library (iCloud Drive, cloud storage, app data) is never searched, also
    /// when it is reached through a link; it is reported with the unreadable roots.
    func testRootInsideHomeLibraryIsRefused() throws {
        let home = root.deletingLastPathComponent().appendingPathComponent("home")
        let cloud = home.appendingPathComponent("Library/CloudStorage/Drive")
        try makeFile("app/node_modules/file.js", in: cloud)
        try makeFile("app/package.json", in: cloud)
        let mobile = home.appendingPathComponent("Library/Mobile Documents/projects")
        try makeFile("app/node_modules/file.js", in: mobile)
        try makeFile("app/package.json", in: mobile)
        let link = home.appendingPathComponent("Drive")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: cloud)
        let library = home.appendingPathComponent("Library")
        let roots = [cloud, mobile, library, link]
        let result = ProjectDependencies.scan(roots: roots, kinds: Set(DependencyKind.allCases), maxDepth: 6, isTrackedByGit: { _ in false }, shouldStop: { false }, home: home)
        XCTAssertEqual(result.found, [])
        XCTAssertEqual(result.unreadableRoots, roots)
        // The same folders outside a Library are searched.
        let elsewhere = home.appendingPathComponent("Projects")
        try makeFile("app/node_modules/file.js", in: elsewhere)
        try makeFile("app/package.json", in: elsewhere)
        let searched = ProjectDependencies.scan(roots: [elsewhere], kinds: Set(DependencyKind.allCases), maxDepth: 6, isTrackedByGit: { _ in false }, shouldStop: { false }, home: home)
        XCTAssertEqual(searched.found.count, 1)
    }

    func testGitFolderIsNotEntered() throws {
        try makeFile("app/.git/hooks/node_modules/file.js")
        try makeFile("app/.git/hooks/package.json")
        XCTAssertEqual(relativePaths(scan()), [])
    }

    func testFileSizesCountRegularFilesOnly() throws {
        let file = try makeFile("dir/a.bin", text: String(repeating: "x", count: 10_000))
        XCTAssertGreaterThanOrEqual(FileSizes.allocated(file), 10_000)
        XCTAssertEqual(FileSizes.allocated(file.deletingLastPathComponent()), 0)
        XCTAssertEqual(FileSizes.folder(file.deletingLastPathComponent()), FileSizes.allocated(file))
    }

    /// A dependency folder that is a repository of its own (a .git folder, or a .git file for a
    /// worktree or submodule) is never offered.
    func testFolderWithItsOwnRepositoryIsNotOffered() throws {
        try makeFile("cloned/node_modules/.git/HEAD")
        try makeFile("cloned/node_modules/lib.js")
        try makeFile("cloned/package.json")
        try makeFile("worktree/build/.git", text: "gitdir: /elsewhere/.git/worktrees/build")
        try makeFile("worktree/build/src.txt")
        try makeFile("worktree/build.gradle")
        try makeFile("app/node_modules/lib.js")
        try makeFile("app/package.json")
        XCTAssertEqual(relativePaths(scan()), ["app/node_modules"])
    }

    /// ~/Library is found whatever its case: on a case-insensitive disk ~/library is the same folder.
    func testLibraryInAnyCaseIsLibrary() throws {
        let home = root.deletingLastPathComponent().appendingPathComponent("home")
        XCTAssertTrue(ProjectDependencies.isInLibrary(home.appendingPathComponent("library/CloudStorage"), home: home))
        XCTAssertTrue(ProjectDependencies.isInLibrary(home.appendingPathComponent("LIBRARY"), home: home))
        XCTAssertFalse(ProjectDependencies.isInLibrary(home.appendingPathComponent("Libraryx/a"), home: home))
        XCTAssertFalse(ProjectDependencies.isInLibrary(home.appendingPathComponent("Projects/library"), home: home))
    }

    func testLowercaseLibraryRootIsRefused() throws {
        let home = root.deletingLastPathComponent().appendingPathComponent("home")
        let cloud = home.appendingPathComponent("Library/CloudStorage/Drive")
        try makeFile("app/node_modules/file.js", in: cloud)
        try makeFile("app/package.json", in: cloud)
        let lowercase = home.appendingPathComponent("library/CloudStorage/Drive")
        let result = ProjectDependencies.scan(roots: [lowercase], kinds: Set(DependencyKind.allCases), maxDepth: 6, isTrackedByGit: { _ in false }, shouldStop: { false }, home: home)
        XCTAssertEqual(result.found, [])
        XCTAssertEqual(result.unreadableRoots, [lowercase])
    }

    /// A Java project edited deep in src/main/java is not old, even if the files near the top are.
    func testEditDeepInTheProjectCounts() throws {
        let project = root.appendingPathComponent("javaapp")
        let old = Date().addingTimeInterval(-200 * 24 * 3600)
        let buildFile = try makeFile("build.gradle", in: project)
        let source = try makeFile("src/main/java/com/acme/app/App.java", in: project)
        try fileManager.setAttributes([.modificationDate: old], ofItemAtPath: buildFile.path)
        try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: source.path)
        let changed = ProjectDependencies.lastChanged(of: project, kinds: Set(DependencyKind.allCases))
        XCTAssertEqual(changed.timeIntervalSinceNow, 0, accuracy: 60)
    }

    /// A source folder that only shares a dependency folder's name (a Java package called build)
    /// is part of the project: its edits count.
    func testSourceFolderNamedLikeADependencyFolderCounts() throws {
        let project = root.appendingPathComponent("tool")
        let old = Date().addingTimeInterval(-200 * 24 * 3600)
        let readme = try makeFile("README.md", in: project)
        let source = try makeFile("src/build/Builder.java", in: project)
        try fileManager.setAttributes([.modificationDate: old], ofItemAtPath: readme.path)
        try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: source.path)
        let changed = ProjectDependencies.lastChanged(of: project, kinds: Set(DependencyKind.allCases))
        XCTAssertEqual(changed.timeIntervalSinceNow, 0, accuracy: 60)
    }

    /// A real dependency folder still does not make a project look used.
    func testProvenDependencyFolderDoesNotCount() throws {
        let project = root.appendingPathComponent("web")
        let old = Date().addingTimeInterval(-200 * 24 * 3600)
        let marker = try makeFile("package.json", in: project)
        try makeFile("node_modules/lib/deep/index.js", in: project)
        try fileManager.setAttributes([.modificationDate: old], ofItemAtPath: marker.path)
        let changed = ProjectDependencies.lastChanged(of: project, kinds: Set(DependencyKind.allCases))
        XCTAssertEqual(changed.timeIntervalSince(old), 0, accuracy: 60)
    }

    /// A project too big to read within the limit has no known age: never ticked on its own.
    func testProjectTooBigToReadHasNoKnownAge() throws {
        let project = root.appendingPathComponent("big")
        for index in 0..<30 {
            try makeFile("src/file\(index).txt", in: project)
        }
        let changed = ProjectDependencies.lastChanged(of: project, kinds: Set(DependencyKind.allCases), entryLimit: 10)
        XCTAssertEqual(changed, Date.distantPast)
        let small = ProjectDependencies.lastChanged(of: project, kinds: Set(DependencyKind.allCases), entryLimit: 1000)
        XCTAssertEqual(small.timeIntervalSinceNow, 0, accuracy: 60)
    }


    /// A monorepo with several dependency folders is dated once, not once per folder.
    func testProjectIsDatedOncePerScan() throws {
        try makeFile("mono/.git/HEAD")
        for name in ["a", "b", "c"] {
            try makeFile("mono/packages/\(name)/package.json")
            try makeFile("mono/packages/\(name)/node_modules/lib.js")
        }
        let ages = ProjectAges()
        let result = ProjectDependencies.scan(roots: [root], kinds: Set(DependencyKind.allCases), maxDepth: 6, isTrackedByGit: { _ in false }, shouldStop: { false }, ages: ages)
        XCTAssertEqual(result.found.count, 3)
        XCTAssertEqual(ages.reads, 1)
        for dependency in result.found {
            XCTAssertEqual(dependency.projectRoot.standardizedFileURL.lastPathComponent, "mono")
        }
    }


    /// Only the project's own top-level Library (any case) is left out of its age; a source folder
    /// called Library deeper down is part of the project.
    func testOnlyTopLevelLibraryIsLeftOutOfTheAge() throws {
        let project = root.appendingPathComponent("lib")
        let old = Date().addingTimeInterval(-200 * 24 * 3600)
        let marker = try makeFile("package.json", in: project)
        try fileManager.setAttributes([.modificationDate: old], ofItemAtPath: marker.path)
        try makeFile("library/new.txt", in: project)
        let kinds = Set(DependencyKind.allCases)
        XCTAssertEqual(ProjectDependencies.lastChanged(of: project, kinds: kinds).timeIntervalSince(old), 0, accuracy: 60)

        try fileManager.removeItem(at: project.appendingPathComponent("library"))
        try makeFile("Sources/Library/Thing.swift", in: project)
        XCTAssertEqual(ProjectDependencies.lastChanged(of: project, kinds: kinds).timeIntervalSinceNow, 0, accuracy: 60)
    }

}
