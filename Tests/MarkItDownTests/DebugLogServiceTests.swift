import Foundation
import XCTest
@testable import MarkItDown

final class DebugLogServiceTests: XCTestCase {
    func testAppendWritesDiagnosticEntry() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = DebugLogService(baseDirectory: directory)
        let entry = DiagnosticEntry(
            title: "Engine load failed",
            message: "Missing Python",
            details: "Python: /missing/bin/python3.12"
        )

        service.append(entry)

        let logURL = try service.logFileURL()
        let contents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("Engine load failed"))
        XCTAssertTrue(contents.contains("Missing Python"))
        XCTAssertTrue(contents.contains("/missing/bin/python3.12"))
    }
}
