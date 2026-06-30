import Foundation
import OSLog

struct DebugLogService {
    private let fileManager: FileManager
    private let baseDirectory: URL?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.markitdown.menubar",
        category: "Diagnostics"
    )

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
    }

    func append(_ entry: DiagnosticEntry) {
        do {
            let url = try logFileURL()
            let data = (entry.formatted + "\n\n").data(using: .utf8) ?? Data()

            if fileManager.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: .atomic)
            }

            logger.error("\(entry.title, privacy: .public): \(entry.message, privacy: .public)")
        } catch {
            logger.error("Failed to write debug log: \(error.localizedDescription, privacy: .public)")
        }
    }

    func logFileURL() throws -> URL {
        let directory: URL
        if let baseDirectory {
            directory = baseDirectory
        } else {
            directory = try fileManager.url(
                for: .libraryDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("MarkItDown", isDirectory: true)
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("debug.log")
    }
}
