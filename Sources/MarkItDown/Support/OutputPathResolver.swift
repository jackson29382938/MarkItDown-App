import Foundation

enum OutputPathResolver {
    static func markdownOutputURL(for sourceURL: URL, fileManager: FileManager = .default) -> URL {
        markdownOutputURL(for: sourceURL, avoiding: [], fileManager: fileManager)
    }

    static func markdownOutputURL(
        for sourceURL: URL,
        avoiding occupiedURLs: Set<URL>,
        fileManager: FileManager = .default
    ) -> URL {
        let directory = sourceURL.deletingLastPathComponent()
        return markdownOutputURL(for: sourceURL, inDirectory: directory, avoiding: occupiedURLs, fileManager: fileManager)
    }

    static func markdownOutputURL(
        for sourceURL: URL,
        inDirectory directory: URL,
        avoiding occupiedURLs: Set<URL> = [],
        fileManager: FileManager = .default
    ) -> URL {
        let occupiedPaths = Set(occupiedURLs.map { $0.standardizedFileURL.path })
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension("md")

        if !outputExists(candidate, occupiedPaths: occupiedPaths, fileManager: fileManager) {
            return candidate
        }

        var suffix = 2
        repeat {
            candidate = directory
                .appendingPathComponent("\(baseName) \(suffix)")
                .appendingPathExtension("md")
            suffix += 1
        } while outputExists(candidate, occupiedPaths: occupiedPaths, fileManager: fileManager)

        return candidate
    }

    static func fallbackOutputDirectory(fileManager: FileManager = .default) throws -> URL {
        let downloads = try fileManager.url(
            for: .downloadsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = downloads.appendingPathComponent("MarkItDown", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func outputExists(
        _ url: URL,
        occupiedPaths: Set<String>,
        fileManager: FileManager
    ) -> Bool {
        occupiedPaths.contains(url.standardizedFileURL.path) || fileManager.fileExists(atPath: url.path)
    }
}
