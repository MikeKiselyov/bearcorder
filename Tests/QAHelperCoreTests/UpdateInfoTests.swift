import XCTest
@testable import QAHelperCore

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
}
