import AppKit
import XCTest
@testable import MarkItDown

final class PasteboardFileWriterTests: XCTestCase {
    func testCopyFileWritesFileURLAndFilenamesPasteboardTypes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("Converted.md")
        try "# Converted".write(to: fileURL, atomically: true, encoding: .utf8)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))

        XCTAssertTrue(PasteboardFileWriter.copyFile(fileURL, to: pasteboard))

        XCTAssertEqual(pasteboard.string(forType: .fileURL), fileURL.standardizedFileURL.absoluteString)
        XCTAssertEqual(
            pasteboard.propertyList(forType: PasteboardFileWriter.filenamesType) as? [String],
            [fileURL.standardizedFileURL.path]
        )
        XCTAssertNil(pasteboard.string(forType: .string))
    }
}
