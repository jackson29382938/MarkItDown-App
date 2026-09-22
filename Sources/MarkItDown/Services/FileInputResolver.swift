import Foundation

struct FileInputResolver {
    enum Mode {
        case userSelection
        case watchedFolder
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func resolveFiles(from urls: [URL], mode: Mode = .userSelection) -> [URL] {
        var resolvedFiles: [URL] = []
        var seenPaths: Set<String> = []

        for url in urls {
            for fileURL in resolveFile(from: url, mode: mode) {
                let key = fileURL.standardizedFileURL.path
                guard seenPaths.insert(key).inserted else { continue }
                resolvedFiles.append(fileURL)
            }
        }

        return resolvedFiles
    }

    private func resolveFile(from url: URL, mode: Mode) -> [URL] {
        let standardizedURL = url.standardizedFileURL
        guard let values = try? standardizedURL.resourceValues(
            forKeys: [.isDirectoryKey, .isRegularFileKey, .isPackageKey, .isHiddenKey]
        ) else {
            return []
        }

        if values.isRegularFile == true {
            return shouldIncludeFile(standardizedURL, isHidden: values.isHidden == true, mode: mode) ? [standardizedURL] : []
        }

        if values.isDirectory == true, values.isPackage != true {
            return resolveDirectory(standardizedURL, mode: mode)
        }

        if values.isPackage == true {
            return shouldIncludeFile(standardizedURL, isHidden: values.isHidden == true, mode: mode) ? [standardizedURL] : []
        }

        return []
    }

    private func resolveDirectory(_ directoryURL: URL, mode: Mode) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  shouldIncludeFile(fileURL, isHidden: values.isHidden == true, mode: mode) else {
                continue
            }
            files.append(fileURL.standardizedFileURL)
        }

        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func shouldIncludeFile(_ url: URL, isHidden: Bool, mode: Mode) -> Bool {
        guard !isHidden else { return false }

        switch mode {
        case .userSelection:
            return true
        case .watchedFolder:
            return !SupportedFileTypes.isMarkdown(url)
        }
    }
}
