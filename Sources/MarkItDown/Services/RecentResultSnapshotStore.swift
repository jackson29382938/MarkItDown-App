import Foundation

/// Keeps a private copy of each recent Markdown result so copy actions still work
/// after the output file has been moved, renamed or deleted.
struct RecentResultSnapshotStore {
    private let directory: URL

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        directory = base
            .appendingPathComponent("MarkItDown", isDirectory: true)
            .appendingPathComponent("RecentSnapshots", isDirectory: true)
    }

    /// The snapshot keeps the original file name so a copied file pastes with the same name.
    func snapshotURL(for result: ConversionResult) -> URL {
        directory
            .appendingPathComponent(result.id.uuidString, isDirectory: true)
            .appendingPathComponent(result.markdownURL.lastPathComponent)
    }

    func existingSnapshotURL(for result: ConversionResult, fileManager: FileManager = .default) -> URL? {
        let url = snapshotURL(for: result)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Copies the current output file into the snapshot store. Returns nil if the output is already gone.
    @discardableResult
    func capture(_ result: ConversionResult, fileManager: FileManager = .default) -> URL? {
        guard fileManager.fileExists(atPath: result.markdownURL.path) else { return nil }

        let destination = snapshotURL(for: result)
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: result.markdownURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// Deletes snapshots for results no longer in the recent list.
    func removeAll(except ids: Set<UUID>, fileManager: FileManager = .default) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        for entry in entries {
            guard let id = UUID(uuidString: entry.lastPathComponent), !ids.contains(id) else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }
}
