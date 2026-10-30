import XCTest
@testable import AppCore

final class UpdateInfoTests: XCTestCase {
    func testParsesNewCommitsNewestFirst() {
        let json = #"""
        {"status":"ahead","ahead_by":2,"behind_by":0,"commits":[
          {"sha":"aaaaaaa1111","commit":{"message":"Add regex tester\n\nDetails"}},
          {"sha":"bbbbbbb2222","commit":{"message":"Fix menu height"}}
        ]}
        """#
        let info = UpdateInfo.parse(compareJSON: Data(json.utf8))
        XCTAssertEqual(info?.newCommitCount, 2)
        XCTAssertEqual(info?.changes, [
            UpdateInfo.Change(title: "Fix menu height", shortSHA: "bbbbbbb"),
            UpdateInfo.Change(title: "Add regex tester", shortSHA: "aaaaaaa"),
        ])
        XCTAssertEqual(info?.isAvailable, true)
    }

    func testUpToDateAndErrors() {
        let identical = UpdateInfo.parse(compareJSON: Data(#"{"status":"identical","ahead_by":0,"commits":[]}"#.utf8))
        XCTAssertEqual(identical?.isAvailable, false)
        XCTAssertNil(UpdateInfo.parse(compareJSON: Data(#"{"message":"Not Found"}"#.utf8)))
        XCTAssertNil(UpdateInfo.compareURL(repository: "", commit: "abc", branch: "main"))
        XCTAssertEqual(UpdateInfo.compareURL(repository: "a/b", commit: "abc", branch: "main")?.absoluteString, "https://api.github.com/repos/a/b/compare/abc...main")
    }

    func testListsMergedPullRequestsWithTheirTitles() {
        let json = #"""
        {"status":"ahead","ahead_by":6,"commits":[
          {"sha":"1111111aaaa","commit":{"message":"Fix crop handles"}},
          {"sha":"2222222bbbb","commit":{"message":"Merge branch 'main' into editor-polish"}},
          {"sha":"3333333cccc","commit":{"message":"Merge pull request #8 from MikeKiselyov/editor-polish\n\nEditors: colors, fill and crop (0.7.0)"}},
          {"sha":"4444444dddd","commit":{"message":"Add 480p"}},
          {"sha":"5555555eeee","commit":{"message":"Merge pull request #9 from MikeKiselyov/export-quality"}},
          {"sha":"6666666ffff","commit":{"message":"README: donate link (#10)"}}
        ]}
        """#
        let info = UpdateInfo.parse(compareJSON: Data(json.utf8))
        XCTAssertEqual(info?.newCommitCount, 6)
        XCTAssertEqual(info?.changeCount, 3)
        XCTAssertEqual(info?.changes, [
            UpdateInfo.Change(title: "README: donate link", shortSHA: "6666666", pullRequest: 10),
            UpdateInfo.Change(title: "Pull request #9", shortSHA: "5555555", pullRequest: 9),
            UpdateInfo.Change(title: "Editors: colors, fill and crop (0.7.0)", shortSHA: "3333333", pullRequest: 8),
        ])
        XCTAssertEqual(info?.changes.first?.url(repository: "a/b")?.absoluteString, "https://github.com/a/b/pull/10")
    }

    func testCommitsWithoutPullRequestsLinkToTheCommit() {
        let json = #"{"status":"ahead","ahead_by":2,"commits":[{"sha":"aaaaaaa1111","commit":{"message":"Merge branch 'main' into x"}},{"sha":"bbbbbbb2222","commit":{"message":"Fix menu height"}}]}"#
        let info = UpdateInfo.parse(compareJSON: Data(json.utf8))
        XCTAssertEqual(info?.changeCount, 1)
        XCTAssertEqual(info?.changes.first?.url(repository: "a/b")?.absoluteString, "https://github.com/a/b/commit/bbbbbbb")
    }
}
