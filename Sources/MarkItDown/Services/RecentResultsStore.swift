import Foundation

struct RecentResultsStore {
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MarkItDown", isDirectory: true)
        if let directory {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            fileURL = directory.appendingPathComponent("recent-results.json")
        } else {
            fileURL = URL(fileURLWithPath: "/tmp/markitdown-recent-results.json")
        }
    }

    func load() -> [ConversionResult] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        return (try? JSONDecoder().decode([ConversionResult].self, from: data)) ?? []
    }

    func save(_ results: [ConversionResult]) {
        guard let data = try? JSONEncoder().encode(results) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
