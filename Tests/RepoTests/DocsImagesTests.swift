import AppCore
import Foundation
import XCTest

/// Pictures stay in step with the docs and What's New: every picture is used somewhere, and every
/// link points at a picture that exists. Old pictures nothing shows any more are deleted.
final class DocsImagesTests: XCTestCase {
    private var root: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    private func files(in folder: String) -> [String] {
        let url = root.appendingPathComponent(folder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        var kept: [String] = []
        for name in names where !name.hasPrefix(".") {
            kept.append(name)
        }
        return kept.sorted()
    }

    private func read(_ path: String) -> String {
        return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    /// README.md and every docs/*.md, where docs/images pictures are shown.
    private var docsText: String {
        var text = read("README.md")
        for name in files(in: "docs") where name.hasSuffix(".md") {
            text += read("docs/\(name)")
        }
        return text
    }

    func testEveryDocsPictureIsUsed() {
        let text = docsText
        for name in files(in: "docs/images") {
            XCTAssertTrue(text.contains("images/\(name)"), "docs/images/\(name) is not shown anywhere: delete it and its line in scripts/dev/readme-media.sh")
        }
    }

    func testEveryDocsLinkHasItsPicture() throws {
        let text = docsText
        let pattern = try NSRegularExpression(pattern: "images/([A-Za-z0-9._-]+\\.(?:png|gif|jpg))")
        let range = NSRange(text.startIndex..., in: text)
        let existing = Set(files(in: "docs/images"))
        for match in pattern.matches(in: text, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[nameRange])
            XCTAssertTrue(existing.contains(name), "a doc shows images/\(name), which does not exist")
        }
    }

    func testEveryWhatsNewPictureIsUsed() {
        let catalog = read("Sources/AppCore/Support/WhatsNewCatalog.swift")
        for name in files(in: WhatsNew.imageFolder) {
            let base = (name as NSString).deletingPathExtension
            XCTAssertTrue(catalog.contains("image: \"\(base)\""), "\(WhatsNew.imageFolder)/\(name) is not in any What's New item: delete it")
        }
    }
}
