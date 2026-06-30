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

    private let conversionService: ConversionService
    private let engineManager: EngineManager
    private let engineUpdater: EngineUpdater
    private let filePanelService: FilePanelService
    private let debugLogService: DebugLogService
    private var isDrainingQueue = false

    init(
        conversionService: ConversionService = ConversionService(),
        engineManager: EngineManager = EngineManager(),
        filePanelService: FilePanelService = FilePanelService(),
        debugLogService: DebugLogService = DebugLogService()
    ) {
        self.conversionService = conversionService
        self.engineManager = engineManager
        self.engineUpdater = EngineUpdater(engineManager: engineManager)
        self.filePanelService = filePanelService
        self.debugLogService = debugLogService
        UserDefaults.standard.register(defaults: ["revealAfterConversion": false])
        refreshEngineState()
    }

    var isConverting: Bool {
        jobs.contains { $0.status == .running || $0.status == .pending }
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

    func enqueue(urls: [URL]) {
        let files = urls.filter { !$0.hasDirectoryPath }
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

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyMarkdown(_ result: ConversionResult) {
        guard let text = try? String(contentsOf: result.markdownURL, encoding: .utf8) else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
                recentResults = Array(recentResults.prefix(8))

                if UserDefaults.standard.bool(forKey: "revealAfterConversion") {
                    reveal(result.markdownURL)
                }
            } catch {
                jobs[index].status = .failed
                jobs[index].completedAt = Date()
                jobs[index].errorMessage = error.localizedDescription
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
