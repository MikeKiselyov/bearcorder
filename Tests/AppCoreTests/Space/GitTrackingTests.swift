import AppCore
import XCTest

/// A dependency folder is offered only when git plainly does not track it. Any failure of git that
/// is not "not a git repository" keeps it; without the developer tools git is never started.
final class GitTrackingTests: XCTestCase {
    var base: URL!
    let fileManager = FileManager.default

    override func setUpWithError() throws {
        base = fileManager.temporaryDirectory.appendingPathComponent("git-\(UUID().uuidString)")
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: base)
    }

    /// node_modules in a project that is a repository (a .git folder in the project).
    func makeRepositoryProject() throws -> URL {
        let project = base.appendingPathComponent("repo")
        try fileManager.createDirectory(at: project.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let folder = project.appendingPathComponent("node_modules")
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func answer(exit: Int32, error: String) -> GitTracking.Answer {
        return GitTracking.Answer(printedPaths: false, exitStatus: exit, errorText: error, timedOut: false)
    }

    func testPrintedPathsMeanTracked() throws {
        let folder = try makeRepositoryProject()
        let tracked = GitTracking.isTracked(folder, gitIsInstalled: true, run: { _ in
            return GitTracking.Answer(printedPaths: true, exitStatus: 0, errorText: "", timedOut: false)
        })
        XCTAssertTrue(tracked)
    }

    func testCleanAnswerWithNoPathsIsNotTracked() throws {
        let folder = try makeRepositoryProject()
        let tracked = GitTracking.isTracked(folder, gitIsInstalled: true, run: { _ in
            return self.answer(exit: 0, error: "")
        })
        XCTAssertFalse(tracked)
    }

    func testNotARepositoryIsNotTracked() throws {
        let folder = try makeRepositoryProject()
        let tracked = GitTracking.isTracked(folder, gitIsInstalled: true, run: { _ in
            return self.answer(exit: 128, error: "fatal: not a git repository (or any of the parent directories): .git\n")
        })
        XCTAssertFalse(tracked)
    }

    func testDubiousOwnershipCountsAsTracked() throws {
        let folder = try makeRepositoryProject()
        let tracked = GitTracking.isTracked(folder, gitIsInstalled: true, run: { _ in
            return self.answer(exit: 128, error: "fatal: detected dubious ownership in repository at '/x'\n")
        })
        XCTAssertTrue(tracked)
    }

    func testMissingDeveloperToolsMessageCountsAsTracked() throws {
        let folder = try makeRepositoryProject()
        let tracked = GitTracking.isTracked(folder, gitIsInstalled: true, run: { _ in
            return self.answer(exit: 1, error: "xcrun: error: invalid active developer path (/Library/Developer/CommandLineTools)\n")
        })
        XCTAssertTrue(tracked)
    }

    func testGitThatCannotStartCountsAsTrackedInARepository() throws {
        let folder = try makeRepositoryProject()
        let tracked = GitTracking.isTracked(folder, gitIsInstalled: true, run: { _ in
            return nil
        })
        XCTAssertTrue(tracked)
    }

    func testTimeoutCountsAsTracked() throws {
        let folder = try makeRepositoryProject()
        let tracked = GitTracking.isTracked(folder, gitIsInstalled: true, run: { _ in
            return GitTracking.Answer(printedPaths: false, exitStatus: 15, errorText: "", timedOut: true)
        })
        XCTAssertTrue(tracked)
    }

    /// Without Command Line Tools or Xcode, /usr/bin/git would show the install dialog: it is not
    /// started, and a folder inside a repository is kept.
    func testWithoutDeveloperToolsGitIsNotStartedAndRepositoryFolderIsKept() throws {
        let folder = try makeRepositoryProject()
        var runs = 0
        let tracked = GitTracking.isTracked(folder, gitIsInstalled: false, run: { _ in
            runs += 1
            return self.answer(exit: 0, error: "")
        })
        XCTAssertEqual(runs, 0)
        XCTAssertTrue(tracked)
    }

    /// A worktree or submodule has a .git file instead of a folder: still a repository.
    func testGitFileAboveCountsAsRepository() throws {
        let project = base.appendingPathComponent("worktree")
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        try "gitdir: /elsewhere/.git/worktrees/x\n".write(to: project.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        let folder = project.appendingPathComponent("node_modules")
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var runs = 0
        let tracked = GitTracking.isTracked(folder, gitIsInstalled: false, run: { _ in
            runs += 1
            return nil
        })
        XCTAssertEqual(runs, 0)
        XCTAssertTrue(tracked)
    }

    /// No .git anywhere above: plainly not tracked, and git is not asked at all.
    func testFolderOutsideAnyRepositoryIsNotTrackedWithoutAskingGit() throws {
        let folder = base.appendingPathComponent("plain/node_modules")
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        // The temp folder must not itself be inside a repository for this test to mean anything.
        XCTAssertFalse(GitTracking.hasRepositoryAbove(folder))
        var runs = 0
        let withoutTools = GitTracking.isTracked(folder, gitIsInstalled: false, run: { _ in
            runs += 1
            return nil
        })
        let withTools = GitTracking.isTracked(folder, gitIsInstalled: true, run: { _ in
            runs += 1
            return GitTracking.Answer(printedPaths: true, exitStatus: 0, errorText: "", timedOut: false)
        })
        XCTAssertFalse(withoutTools)
        XCTAssertFalse(withTools)
        XCTAssertEqual(runs, 0)
    }

    func testDeveloperToolsAreFoundByTheirGit() throws {
        let tools = base.appendingPathComponent("CommandLineTools")
        XCTAssertFalse(GitTracking.isGitInstalled(developerFolders: [tools]))
        try fileManager.createDirectory(at: tools.appendingPathComponent("usr/bin"), withIntermediateDirectories: true)
        try "".write(to: tools.appendingPathComponent("usr/bin/git"), atomically: true, encoding: .utf8)
        XCTAssertTrue(GitTracking.isGitInstalled(developerFolders: [base.appendingPathComponent("Xcode.app/Contents/Developer"), tools]))
    }
}
