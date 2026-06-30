import Foundation

enum QuickActionInstaller {
    private static let workflowName = "Convert to Markdown.workflow"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installURL.path)
    }

    static var installURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services/\(workflowName)")
    }

    static func install() throws {
        guard let bundledWorkflow = Bundle.main.url(
            forResource: "Convert to Markdown",
            withExtension: "workflow",
            subdirectory: "QuickAction"
        ) else {
            throw InstallError.missingBundledWorkflow
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: installURL.path) {
            try fileManager.removeItem(at: installURL)
        }
        try fileManager.copyItem(at: bundledWorkflow, to: installURL)
    }

    static func uninstall() throws {
        guard isInstalled else { return }
        try FileManager.default.removeItem(at: installURL)
    }

    enum InstallError: LocalizedError {
        case missingBundledWorkflow

        var errorDescription: String? {
            switch self {
            case .missingBundledWorkflow:
                return "The bundled Finder Quick Action workflow was not found in the app."
            }
        }
    }
}
