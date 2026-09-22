import XCTest
@testable import MarkItDown

final class CombineMarkdownServiceTests: XCTestCase {
    func testMergeBlankLineSeparator() {
        let merged = CombineMarkdownService.merge(
            sections: [
                (fileName: "a", markdown: "Hello"),
                (fileName: "b", markdown: "World")
            ],
            style: .blankLine
        )
        XCTAssertEqual(merged, "Hello\n\nWorld\n")
    }

    func testMergeFilenameHeading() {
        let merged = CombineMarkdownService.merge(
            sections: [
                (fileName: "Intro", markdown: "One"),
                (fileName: "Body", markdown: "Two")
            ],
            style: .filenameHeading
        )
        XCTAssertEqual(merged, "## Intro\n\nOne\n\n## Body\n\nTwo\n")
    }

    func testAlphabeticalOrder() {
        let urls = [
            URL(fileURLWithPath: "/tmp/b.md"),
            URL(fileURLWithPath: "/tmp/a.md")
        ]
        let ordered = CombineMarkdownService.orderedSources(urls, order: .alphabetical)
        XCTAssertEqual(ordered.map(\.lastPathComponent), ["a.md", "b.md"])
    }
}
