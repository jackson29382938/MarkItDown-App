import Foundation
import XCTest

final class PythonWorkerIntegrationTests: XCTestCase {
    func testWorkerConvertsTextFixtureWhenEnginePathIsProvided() throws {
        guard let enginePath = ProcessInfo.processInfo.environment["MARKITDOWN_TEST_ENGINE"],
              let pythonPath = ProcessInfo.processInfo.environment["MARKITDOWN_TEST_PYTHON"],
              let workerPath = ProcessInfo.processInfo.environment["MARKITDOWN_TEST_WORKER"] else {
            throw XCTSkip("Set MARKITDOWN_TEST_ENGINE, MARKITDOWN_TEST_PYTHON, and MARKITDOWN_TEST_WORKER to run worker integration tests.")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let source = directory.appendingPathComponent("sample.txt")
        let output = directory.appendingPathComponent("sample.md")
        try "hello markitdown".write(to: source, atomically: true, encoding: .utf8)

        let request = [
            "inputPath": source.path,
            "outputPath": output.path,
            "enginePath": enginePath
        ]
        let requestData = try JSONSerialization.data(withJSONObject: request)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [workerPath]
        process.environment = [
            "PYTHONNOUSERSITE": "1",
            "PYTHONPATH": URL(fileURLWithPath: enginePath).appendingPathComponent("site-packages").path
        ]

        let input = Pipe()
        let stdout = Pipe()
        process.standardInput = input
        process.standardOutput = stdout

        try process.run()
        input.fileHandleForWriting.write(requestData)
        input.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        let responseData = stdout.fileHandleForReading.readDataToEndOfFile()
        let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        XCTAssertEqual(response?["success"] as? Bool, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }
}
