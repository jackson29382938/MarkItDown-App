import Foundation
import XCTest
@testable import MarkItDown

final class FileInputResolverTests: XCTestCase {
    func testKeepsRegularFilesFromSelection() throws {
        let directory = try makeTemporaryDirectory()
        let file = try makeFile(named: "Report.pdf", in: directory)

        let files = FileInputResolver().resolveFiles(from: [file])

        XCTAssertEqual(files, [file.standardizedFileURL])
    }

    func testExpandsDirectoriesRecursivelyInStableOrder() throws {
        let directory = try makeTemporaryDirectory()
        let nested = directory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let second = try makeFile(named: "B.docx", in: nested)
        let first = try makeFile(named: "A.pdf", in: directory)

        let files = FileInputResolver().resolveFiles(from: [directory])

        XCTAssertEqual(files, [first.standardizedFileURL, second.standardizedFileURL])
    }

    func testDeduplicatesFilesAcrossInputs() throws {
        let directory = try makeTemporaryDirectory()
        let file = try makeFile(named: "Report.pdf", in: directory)

        let files = FileInputResolver().resolveFiles(from: [directory, file])

        XCTAssertEqual(files, [file.standardizedFileURL])
    }

    func testWatchedFolderModeSkipsGeneratedMarkdownFiles() throws {
        let directory = try makeTemporaryDirectory()
        let source = try makeFile(named: "Report.pdf", in: directory)
        _ = try makeFile(named: "Report.md", in: directory)

        let files = FileInputResolver().resolveFiles(from: [directory], mode: .watchedFolder)

        XCTAssertEqual(files, [source.standardizedFileURL])
    }

    private func makeFile(named name: String, in directory: URL) throws -> URL {
        let file = directory.appendingPathComponent(name)
        try Data(name.utf8).write(to: file)
        return file
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
