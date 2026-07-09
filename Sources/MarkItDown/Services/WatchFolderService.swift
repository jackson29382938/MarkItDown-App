import Darwin
import Foundation

final class WatchFolderService {
    enum State: Equatable {
        case inactive
        case watching(URL)
        case failed(String)
    }

    var onFilesDetected: (([URL]) -> Void)?
    var onStateChanged: ((State) -> Void)?

    private let fileManager: FileManager
    private let resolver: FileInputResolver
    private let queue = DispatchQueue(label: "app.markitdown.watch-folder", qos: .utility)
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var watchedURL: URL?
    private var knownFilePaths: Set<String> = []
    private var pendingScan: DispatchWorkItem?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.resolver = FileInputResolver(fileManager: fileManager)
    }

    deinit {
        stop()
    }

    func start(watching directoryURL: URL) {
        stop()

        let standardizedURL = directoryURL.standardizedFileURL
        guard isReadableDirectory(standardizedURL) else {
            transition(to: .failed("The watch folder could not be read."))
            return
        }

        let descriptor = open(standardizedURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            transition(to: .failed(String(cString: strerror(errno))))
            return
        }

        fileDescriptor = descriptor
        watchedURL = standardizedURL
        knownFilePaths = currentFilePaths(in: standardizedURL)

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: queue
        )
        self.source = source

        source.setEventHandler { [weak self] in
            self?.handleFileSystemEvent()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()

        transition(to: .watching(standardizedURL))
    }

    func stop() {
        pendingScan?.cancel()
        pendingScan = nil
        source?.cancel()
        source = nil
        fileDescriptor = -1
        watchedURL = nil
        knownFilePaths = []
        transition(to: .inactive)
    }

    private func handleFileSystemEvent() {
        guard let source else { return }
        let flags = source.data

        if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
            stop()
            transition(to: .failed("The watch folder is no longer available."))
            return
        }

        scheduleScan()
    }

    private func scheduleScan() {
        pendingScan?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.scanForNewFiles()
        }
        pendingScan = workItem
        queue.asyncAfter(deadline: .now() + .seconds(1), execute: workItem)
    }

    private func scanForNewFiles() {
        guard let watchedURL else { return }

        let files = resolver.resolveFiles(from: [watchedURL], mode: .watchedFolder)
        let currentPaths = Set(files.map { $0.standardizedFileURL.path })
        let newFiles = files.filter { !knownFilePaths.contains($0.standardizedFileURL.path) }
        knownFilePaths = currentPaths

        guard !newFiles.isEmpty else { return }
        onFilesDetected?(newFiles)
    }

    private func currentFilePaths(in directoryURL: URL) -> Set<String> {
        Set(
            resolver
                .resolveFiles(from: [directoryURL], mode: .watchedFolder)
                .map { $0.standardizedFileURL.path }
        )
    }

    private func isReadableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) &&
            isDirectory.boolValue &&
            fileManager.isReadableFile(atPath: url.path)
    }

    private func transition(to state: State) {
        onStateChanged?(state)
    }
}
