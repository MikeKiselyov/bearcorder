import XCTest
@testable import AppCore

final class UpdateProgressTests: XCTestCase {
    private let fetched = "==> git fetch\nFrom https://github.com/x/y\n==> updating main\nFast-forward\n"
    private let building = "==> build\n==> swift build (release)\n[8/10] Compiling App\n"
    private let built = "Build of product 'App' complete! (91.39s)\n==> version 0.18.0 (90)\n==> assembling /x/build/App.app\n"
    private let signed = "==> rendering icon\n==> signing with: Someone\n==> done: /x/build/App.app\n"

    func testEmptyLogStartsAtZero() {
        let progress = UpdateProgress.estimate(log: "", elapsedInBuild: 0, expectedBuild: 100)
        XCTAssertEqual(progress.step, .downloading)
        XCTAssertEqual(progress.percent, 0)
    }

    func testDownloadingStaysUnderTheBuild() {
        let progress = UpdateProgress.estimate(log: fetched, elapsedInBuild: 0, expectedBuild: 100)
        XCTAssertEqual(progress.step, .downloading)
        XCTAssertEqual(progress.percent, 4)
    }

    func testBuildingFollowsTheTime() {
        let start = UpdateProgress.estimate(log: fetched + building, elapsedInBuild: 0, expectedBuild: 100)
        XCTAssertEqual(start.step, .building)
        XCTAssertEqual(start.percent, 5)
        let half = UpdateProgress.estimate(log: fetched + building, elapsedInBuild: 50, expectedBuild: 100)
        XCTAssertEqual(half.percent, 47)
    }

    /// A build slower than the last one stops short of the next step instead of looking done.
    func testSlowBuildNeverReachesTheNextStep() {
        let progress = UpdateProgress.estimate(log: fetched + building, elapsedInBuild: 500, expectedBuild: 100)
        XCTAssertEqual(progress.step, .building)
        XCTAssertEqual(progress.percent, 85)
    }

    func testNoKnownBuildTimeUsesTheDefault() {
        let progress = UpdateProgress.estimate(log: fetched + building, elapsedInBuild: 75, expectedBuild: nil)
        XCTAssertEqual(progress.percent, 47)
    }

    func testFinishingAndInstallingAfterTheBuild() {
        let finishing = UpdateProgress.estimate(log: fetched + building + built, elapsedInBuild: 90, expectedBuild: 100)
        XCTAssertEqual(finishing.step, .finishing)
        XCTAssertEqual(finishing.percent, 92)
        let signedProgress = UpdateProgress.estimate(log: fetched + building + built + signed, elapsedInBuild: 90, expectedBuild: 100)
        XCTAssertEqual(signedProgress.percent, 96)
        let installing = UpdateProgress.estimate(log: fetched + building + built + signed + "==> replacing /Applications/App.app\n", elapsedInBuild: 90, expectedBuild: 100)
        XCTAssertEqual(installing.step, .installing)
        XCTAssertEqual(installing.percent, 97)
    }

    /// Compiler errors after "==> build" keep it on the build step; the failure itself comes from the exit code.
    func testFailedBuildStaysOnTheBuild() {
        let log = fetched + building + "error: cannot find 'x' in scope\nerror: fatalError\n"
        let progress = UpdateProgress.estimate(log: log, elapsedInBuild: 10, expectedBuild: 100)
        XCTAssertEqual(progress.step, .building)
    }

    func testSameProgressIsNotSetAgain() {
        let shown = UpdateProgress(step: .building, percent: 47)
        XCTAssertNil(UpdateProgress.next(shown: shown, read: shown))
    }

    func testProgressNeverGoesBack() {
        let shown = UpdateProgress(step: .building, percent: 47)
        XCTAssertNil(UpdateProgress.next(shown: shown, read: UpdateProgress(step: .downloading, percent: 0)))
    }

    func testProgressMovesOnAHigherPercentOrANewStep() {
        let shown = UpdateProgress(step: .building, percent: 47)
        let higher = UpdateProgress(step: .building, percent: 48)
        XCTAssertEqual(UpdateProgress.next(shown: shown, read: higher), higher)
        let built = UpdateProgress(step: .finishing, percent: 90)
        let version = UpdateProgress(step: .finishing, percent: 90)
        XCTAssertNil(UpdateProgress.next(shown: built, read: version))
        let nextStep = UpdateProgress(step: .installing, percent: 90)
        XCTAssertEqual(UpdateProgress.next(shown: built, read: nextStep), nextStep)
    }

    func testReadsTheBuildTime() {
        XCTAssertEqual(UpdateProgress.buildSeconds(inLog: fetched + building + built), 91.39)
        XCTAssertNil(UpdateProgress.buildSeconds(inLog: fetched + building))
    }

    /// A retry rebuilds almost nothing; its time would make the next full build sit at the cap.
    func testIgnoresABuildThatRebuiltNothing() {
        XCTAssertNil(UpdateProgress.buildSeconds(inLog: "Build of product 'App' complete! (0.62s)\n"))
    }
}
