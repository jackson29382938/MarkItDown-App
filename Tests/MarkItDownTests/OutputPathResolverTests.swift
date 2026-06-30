import Foundation
import XCTest
@testable import MarkItDown

final class OutputPathResolverTests: XCTestCase {
    func testUsesSourceBaseNameWithMarkdownExtension() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("Report.pdf")

        let output = OutputPathResolver.markdownOutputURL(for: source)

        XCTAssertEqual(output.lastPathComponent, "Report.md")
    }

    func testAddsNumberedSuffixWhenOutputExists() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("Report.pdf")
        FileManager.default.createFile(
            atPath: directory.appendingPathComponent("Report.md").path,
            contents: Data()
        )
        FileManager.default.createFile(
            atPath: directory.appendingPathComponent("Report 2.md").path,
            contents: Data()
        )

        let output = OutputPathResolver.markdownOutputURL(for: source)

        XCTAssertEqual(output.lastPathComponent, "Report 3.md")
    }

    func testAvoidsReservedOutputPathsBeforeFilesExist() throws {
        let directory = try makeTemporaryDirectory()
        let source = directory.appendingPathComponent("Report.docx")
        let reserved = Set([directory.appendingPathComponent("Report.md")])

        let output = OutputPathResolver.markdownOutputURL(for: source, avoiding: reserved)

        XCTAssertEqual(output.lastPathComponent, "Report 2.md")
    }

    func testCanResolveOutputInsideFallbackDirectory() throws {
        let sourceDirectory = try makeTemporaryDirectory()
        let fallbackDirectory = try makeTemporaryDirectory()
        let source = sourceDirectory.appendingPathComponent("Nature_MNPs_Brains.pdf")

        let output = OutputPathResolver.markdownOutputURL(for: source, inDirectory: fallbackDirectory)

        XCTAssertEqual(output.deletingLastPathComponent(), fallbackDirectory)
        XCTAssertEqual(output.lastPathComponent, "Nature_MNPs_Brains.md")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
