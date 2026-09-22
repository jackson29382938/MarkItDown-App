import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var jobs: [ConversionJob] = []
    @Published private(set) var recentResults: [ConversionResult] = []
    @Published private(set) var engineManifest: EngineManifest?
    @Published private(set) var engineError: String?
    @Published private(set) var diagnostics: [DiagnosticEntry] = []
    @Published var updateStatus: EngineUpdateStatus = .idle
    @Published private(set) var toastMessage: String?
    @Published private(set) var shortcutConflictMessages: [ShortcutKind: String] = [:]
    @Published private(set) var watchedFolderURL: URL?
    @Published private(set) var isWatchFolderActive = false
    @Published private(set) var watchFolderError: String?
    @Published var combineItems: [CombineItem] = []
    @Published private(set) var isCombining = false

    private let conversionService: ConversionService
    private let engineManager: EngineManager
    private let engineUpdater: EngineUpdater
    private let filePanelService: FilePanelService
    private let fileInputResolver: FileInputResolver
    private let watchFolderService: WatchFolderService
    private let debugLogService: DebugLogService
    private let recentResultsStore: RecentResultsStore
    private var isDrainingQueue = false
    private var toastTask: Task<Void, Never>?
    private var pendingCombineURLs: [URL] = []
    private var combineFlushTask: Task<Void, Never>?

    init(
        conversionService: ConversionService = ConversionService(),
        engineManager: EngineManager = EngineManager(),
        filePanelService: FilePanelService = FilePanelService(),
        fileInputResolver: FileInputResolver = FileInputResolver(),
        watchFolderService: WatchFolderService = WatchFolderService(),
        debugLogService: DebugLogService = DebugLogService(),
        recentResultsStore: RecentResultsStore = RecentResultsStore()
    ) {
        self.conversionService = conversionService
        self.engineManager = engineManager
        self.engineUpdater = EngineUpdater(engineManager: engineManager)
        self.filePanelService = filePanelService
        self.fileInputResolver = fileInputResolver
        self.watchFolderService = watchFolderService
        self.debugLogService = debugLogService
        self.recentResultsStore = recentResultsStore
        AppSettings.registerDefaults()
        AppSettings.migrateIfNeeded()
        configureWatchFolderCallbacks()
        recentResults = Array(recentResultsStore.load().prefix(AppSettings.recentResultsLimit))
        refreshEngineState()
        restoreWatchFolderFromSettings()
    }

    var isConverting: Bool {
        activeJobCount > 0 || isCombining
    }

    var activeJobCount: Int {
        jobs.filter { $0.status == .pending || $0.status == .running }.count
    }

    var queueJobs: [ConversionJob] {
        jobs.filter { $0.status == .pending || $0.status == .running || $0.status == .failed }
    }

    var statusSystemImage: String {
        if isConverting {
            return "arrow.triangle.2.circlepath"
        }
        if hasAttention {
            return "exclamationmark.triangle"
        }
        if !recentResults.isEmpty {
            return "checkmark.circle"
        }
        return "doc.text"
    }

    var currentEngineVersion: String {
        engineManifest?.markitdownVersion ?? "Unknown"
    }

    var hasAttention: Bool {
        engineError != nil ||
            jobs.contains(where: { $0.status == .failed }) ||
            {
                if case .failed = updateStatus { return true }
                return false
            }()
    }

    var latestDiagnostic: DiagnosticEntry? {
        diagnostics.first
    }

    private var reservedOutputURLs: Set<URL> {
        Set(jobs.map(\.outputURL)).union(recentResults.map(\.markdownURL))
    }

    func chooseFiles() {
        enqueue(urls: filePanelService.chooseFiles())
    }

    func chooseWatchFolder() {
        guard let url = filePanelService.chooseFolder() else { return }
        setWatchFolder(url)
    }

    @discardableResult
    func pickFiles() -> [URL] {
        filePanelService.chooseFiles()
    }

    func enqueue(urls: [URL]) {
        let files = fileInputResolver.resolveFiles(from: urls)
        guard !files.isEmpty else { return }

        var reservedOutputs = Set(jobs.map(\.outputURL))
        let newJobs = files.map { sourceURL in
            let outputURL = OutputPathResolver.markdownOutputURL(
                for: sourceURL,
                avoiding: reservedOutputs
            )
            reservedOutputs.insert(outputURL)
            return ConversionJob(sourceURL: sourceURL, outputURL: outputURL)
        }
        jobs.append(contentsOf: newJobs)
        drainQueueIfNeeded()
    }

    func addCombineFiles(_ urls: [URL]) {
        let files = fileInputResolver.resolveFiles(from: urls)
        for file in files {
            guard !combineItems.contains(where: { $0.url.path == file.path }) else { continue }
            combineItems.append(CombineItem(url: file))
        }
    }

    func combineFromPanel() {
        let urls = combineItems.map(\.url)
        guard !urls.isEmpty else { return }
        Task {
            await performCombine(urls: urls, preservePanelOrder: true, clearPanelOnSuccess: true)
        }
    }

    /// Batches Finder Quick Action URLs that may arrive as separate `open` calls.
    func enqueueCombine(urls: [URL]) {
        pendingCombineURLs.append(contentsOf: urls)
        combineFlushTask?.cancel()
        combineFlushTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let batch = pendingCombineURLs
            pendingCombineURLs.removeAll()
            guard !batch.isEmpty else { return }
            await performCombine(urls: batch, preservePanelOrder: false, clearPanelOnSuccess: false)
        }
    }

    func setWatchFolder(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        watchedFolderURL = standardizedURL
        watchFolderError = nil
        AppSettings.watchFolderURL = standardizedURL
        AppSettings.watchFolderEnabled = true
        watchFolderService.start(watching: standardizedURL)
    }

    func setWatchFolderEnabled(_ enabled: Bool) {
        AppSettings.watchFolderEnabled = enabled

        guard enabled else {
            watchFolderService.stop()
            return
        }

        if let watchedFolderURL {
            watchFolderService.start(watching: watchedFolderURL)
        } else if let savedURL = AppSettings.watchFolderURL {
            watchedFolderURL = savedURL
            watchFolderService.start(watching: savedURL)
        } else {
            AppSettings.watchFolderEnabled = false
            isWatchFolderActive = false
            watchFolderError = "Choose a folder to start watching."
        }
    }

    func clearWatchFolder() {
        watchFolderService.stop()
        watchedFolderURL = nil
        watchFolderError = nil
        AppSettings.watchFolderURL = nil
        AppSettings.watchFolderEnabled = false
    }

    func retryJob(_ job: ConversionJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index].status = .pending
        jobs[index].errorMessage = nil
        jobs[index].startedAt = nil
        jobs[index].completedAt = nil
        jobs[index].result = nil
        drainQueueIfNeeded()
    }

    func trimRecentResultsToLimit() {
        let limit = AppSettings.recentResultsLimit
        recentResults = Array(recentResults.prefix(limit))
        persistRecentResults()
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyMarkdownText(_ result: ConversionResult) {
        guard let text = try? String(contentsOf: result.markdownURL, encoding: .utf8) else {
            showToast("Copy failed")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showToast("Markdown text copied")
    }

    func copyMarkdownFile(_ result: ConversionResult) {
        guard PasteboardFileWriter.copyFile(result.markdownURL) else {
            showToast("Copy failed")
            return
        }
        showToast("Markdown file copied")
    }

    func showToast(_ message: String) {
        toastMessage = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            toastMessage = nil
        }
    }

    func updateShortcutConflictMessages(_ messages: [ShortcutKind: String]) {
        shortcutConflictMessages = messages
    }

    func checkForEngineUpdates() {
        guard case .checking = updateStatus else {
            updateStatus = .checking
            Task {
                do {
                    updateStatus = try await engineUpdater.latestReleaseCompared(to: currentEngineVersion)
                } catch {
                    updateStatus = .failed(error.localizedDescription)
                    recordDiagnostic(
                        title: "Engine update check failed",
                        message: error.localizedDescription,
                        details: diagnosticDetails(error: error)
                    )
                }
            }
            return
        }
    }

    func installAvailableUpdate() {
        guard case .available(let release) = updateStatus else { return }

        updateStatus = .installing(release)
        Task {
            do {
                let manifest = try await engineUpdater.install(release: release)
                engineManifest = manifest
                engineError = nil
                updateStatus = .installed(manifest)
            } catch {
                updateStatus = .failed(error.localizedDescription)
                recordDiagnostic(
                    title: "Engine update install failed",
                    message: error.localizedDescription,
                    details: diagnosticDetails(error: error)
                )
            }
        }
    }

    func refreshEngineState() {
        do {
            engineManifest = try engineManager.activeEngine().manifest
            engineError = nil
        } catch {
            engineManifest = nil
            engineError = error.localizedDescription
            recordDiagnostic(
                title: "Engine load failed",
                message: error.localizedDescription,
                details: diagnosticDetails(error: error)
            )
        }
    }

    func copyLatestDebugInfo() {
        guard let latestDiagnostic else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(latestDiagnostic.formatted, forType: .string)
    }

    func revealDebugLog() {
        guard let url = try? debugLogService.logFileURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func clearDiagnostics() {
        diagnostics.removeAll()
    }

    private func performCombine(
        urls: [URL],
        preservePanelOrder: Bool,
        clearPanelOnSuccess: Bool
    ) async {
        guard !isCombining else {
            showToast("Combine already in progress")
            return
        }

        var files = fileInputResolver.resolveFiles(from: urls)
        guard !files.isEmpty else {
            showToast("No files to combine")
            return
        }

        if !preservePanelOrder {
            files = CombineMarkdownService.orderedSources(files, order: AppSettings.combineFinderOrder)
        }

        guard let outputURL = await CombineDestinationPicker.resolveOutputURL(for: files) else {
            return
        }

        isCombining = true
        defer { isCombining = false }

        do {
            let runtime = try engineManager.activeEngine()
            engineManifest = runtime.manifest
            engineError = nil

            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MarkItDown-Combine-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDirectory) }

            var sections: [(fileName: String, markdown: String)] = []
            var individualResults: [ConversionResult] = []
            var occupiedOutputs = reservedOutputURLs
            let started = Date()

            for sourceURL in files {
                let fileName = sourceURL.deletingPathExtension().lastPathComponent
                let markdownText: String

                if SupportedFileTypes.isMarkdown(sourceURL) {
                    markdownText = try String(contentsOf: sourceURL, encoding: .utf8)
                } else if AppSettings.combineWriteIndividualFiles {
                    let individualURL = OutputPathResolver.markdownOutputURL(
                        for: sourceURL,
                        avoiding: occupiedOutputs
                    )
                    occupiedOutputs.insert(individualURL)
                    let individual = try await conversionService.convert(
                        sourceURL: sourceURL,
                        outputURL: individualURL,
                        using: runtime
                    )
                    individualResults.append(individual)
                    markdownText = try String(contentsOf: individual.markdownURL, encoding: .utf8)
                } else {
                    let tempOutput = tempDirectory
                        .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
                        .appendingPathExtension("md")
                    let tempResult = try await conversionService.convert(
                        sourceURL: sourceURL,
                        outputURL: tempOutput,
                        using: runtime
                    )
                    markdownText = try String(contentsOf: tempResult.markdownURL, encoding: .utf8)
                }

                sections.append((fileName: fileName, markdown: markdownText))
            }

            let merged = CombineMarkdownService.merge(
                sections: sections,
                style: AppSettings.combineSeparatorStyle
            )
            guard !merged.isEmpty else {
                throw CombineError.emptyResult
            }

            try merged.write(to: outputURL, atomically: true, encoding: .utf8)

            let elapsed = Date().timeIntervalSince(started)
            let result = ConversionResult(
                sourceURL: files[0],
                markdownURL: outputURL,
                engineVersion: runtime.manifest.markitdownVersion,
                elapsedTime: elapsed
            )
            recentResults.insert(result, at: 0)
            for individual in individualResults.reversed() {
                recentResults.insert(individual, at: 0)
            }
            trimRecentResultsToLimit()

            if AppSettings.revealAfterConversion {
                reveal(outputURL)
            }
            applyAutoCopy(for: result)
            ConversionNotificationService.notifyConversionSucceeded(result)
            showToast("Combined \(files.count) files")

            if clearPanelOnSuccess {
                combineItems.removeAll()
            }
        } catch {
            ConversionNotificationService.notifyConversionFailed(
                fileName: "Combine",
                message: error.localizedDescription
            )
            recordDiagnostic(
                title: "Combine failed",
                message: error.localizedDescription,
                details: diagnosticDetails(error: error)
            )
            showToast("Combine failed")
        }
    }

    private func drainQueueIfNeeded() {
        guard !isDrainingQueue else { return }
        isDrainingQueue = true

        Task {
            await drainQueue()
            isDrainingQueue = false
        }
    }

    private func drainQueue() async {
        while let index = jobs.firstIndex(where: { $0.status == .pending }) {
            jobs[index].status = .running
            jobs[index].startedAt = Date()

            do {
                let runtime = try engineManager.activeEngine()
                engineManifest = runtime.manifest
                engineError = nil

                let result = try await convertWithWritableFallback(job: jobs[index], runtime: runtime)

                jobs[index].status = .succeeded
                jobs[index].completedAt = Date()
                jobs[index].result = result
                recentResults.insert(result, at: 0)
                trimRecentResultsToLimit()

                if AppSettings.revealAfterConversion {
                    reveal(result.markdownURL)
                }

                applyAutoCopy(for: result)
                ConversionNotificationService.notifyConversionSucceeded(result)
                let completedJobID = jobs[index].id
                jobs.removeAll { $0.id == completedJobID }
            } catch {
                jobs[index].status = .failed
                jobs[index].completedAt = Date()
                jobs[index].errorMessage = error.localizedDescription
                ConversionNotificationService.notifyConversionFailed(
                    fileName: jobs[index].sourceURL.lastPathComponent,
                    message: error.localizedDescription
                )
                recordDiagnostic(
                    title: "Conversion failed",
                    message: error.localizedDescription,
                    details: diagnosticDetails(
                        error: error,
                        sourceURL: jobs[index].sourceURL,
                        outputURL: jobs[index].outputURL
                    )
                )
            }
        }
    }

    private func configureWatchFolderCallbacks() {
        watchFolderService.onFilesDetected = { [weak self] urls in
            Task { @MainActor in
                self?.enqueue(urls: urls)
            }
        }

        watchFolderService.onStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.applyWatchFolderState(state)
            }
        }
    }

    private func restoreWatchFolderFromSettings() {
        watchedFolderURL = AppSettings.watchFolderURL
        guard AppSettings.watchFolderEnabled, let watchedFolderURL else {
            isWatchFolderActive = false
            watchFolderError = nil
            return
        }

        watchFolderService.start(watching: watchedFolderURL)
    }

    private func applyWatchFolderState(_ state: WatchFolderService.State) {
        switch state {
        case .inactive:
            isWatchFolderActive = false
            watchFolderError = nil
        case .watching(let url):
            watchedFolderURL = url
            isWatchFolderActive = true
            watchFolderError = nil
        case .failed(let message):
            isWatchFolderActive = false
            watchFolderError = message
            AppSettings.watchFolderEnabled = false
            recordDiagnostic(
                title: "Watch folder unavailable",
                message: message,
                details: [
                    "Watch folder: \(watchedFolderURL?.path ?? "unset")",
                    "Error: \(message)"
                ].joined(separator: "\n")
            )
        }
    }

    private func applyAutoCopy(for result: ConversionResult) {
        switch AppSettings.autoCopyMode {
        case .none:
            break
        case .text:
            copyMarkdownText(result)
        case .file:
            copyMarkdownFile(result)
        }
    }

    private func persistRecentResults() {
        recentResultsStore.save(recentResults)
    }

    private func convertWithWritableFallback(job: ConversionJob, runtime: EngineRuntime) async throws -> ConversionResult {
        do {
            return try await conversionService.convert(
                sourceURL: job.sourceURL,
                outputURL: job.outputURL,
                using: runtime
            )
        } catch let error as ConversionServiceError where error.isOutputPermissionError {
            let fallbackDirectory = try OutputPathResolver.fallbackOutputDirectory()
            let fallbackURL = OutputPathResolver.markdownOutputURL(
                for: job.sourceURL,
                inDirectory: fallbackDirectory,
                avoiding: reservedOutputURLs
            )

            let result = try await conversionService.convert(
                sourceURL: job.sourceURL,
                outputURL: fallbackURL,
                using: runtime
            )

            recordDiagnostic(
                title: "Output folder fallback used",
                message: "The source folder blocked writing, so Markdown was saved to Downloads/MarkItDown.",
                details: [
                    "Source: \(job.sourceURL.path)",
                    "Blocked output: \(job.outputURL.path)",
                    "Fallback output: \(fallbackURL.path)",
                    "",
                    "Original error:",
                    error.localizedDescription,
                    error.debugOutput ?? ""
                ].joined(separator: "\n")
            )

            return result
        }
    }

    private func recordDiagnostic(title: String, message: String, details: String) {
        let entry = DiagnosticEntry(title: title, message: message, details: details)
        diagnostics.insert(entry, at: 0)
        diagnostics = Array(diagnostics.prefix(20))
        debugLogService.append(entry)
    }

    private func diagnosticDetails(error: Error, sourceURL: URL? = nil, outputURL: URL? = nil) -> String {
        var lines: [String] = [
            "App bundle: \(Bundle.main.bundleURL.path)",
            "Resources: \(Bundle.main.resourceURL?.path ?? "unavailable")",
            "User engine: \(engineManager.currentUserEngineURL().path)",
            "Engine version: \(currentEngineVersion)"
        ]

        if let sourceURL {
            lines.append("Source: \(sourceURL.path)")
        }
        if let outputURL {
            lines.append("Output: \(outputURL.path)")
        }

        if let runtime = try? engineManager.activeEngine() {
            lines.append("Active engine: \(runtime.rootURL.path)")
            lines.append("Python: \(runtime.pythonURL.path)")
            lines.append("Site packages: \(runtime.sitePackagesURL.path)")
            lines.append("Worker: \(runtime.workerURL.path)")
        }

        if let conversionError = error as? ConversionServiceError,
           let debugOutput = conversionError.debugOutput,
           !debugOutput.isEmpty {
            lines.append("")
            lines.append("Worker debug output:")
            lines.append(debugOutput)
        } else {
            lines.append("")
            lines.append("Swift error:")
            lines.append(String(reflecting: error))
        }

        return lines.joined(separator: "\n")
    }
}

private enum CombineError: LocalizedError {
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .emptyResult:
            return "Nothing to combine — all selected files were empty."
        }
    }
}
