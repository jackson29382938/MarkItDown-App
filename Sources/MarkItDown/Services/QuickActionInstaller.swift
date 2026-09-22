import AppKit
import Foundation

enum QuickActionKind: String, CaseIterable {
    case convert = "Convert to Markdown"
    case combine = "Combine Markdown"

    var workflowFileName: String { "\(rawValue).workflow" }

    var resourceName: String { rawValue }

    var host: String {
        switch self {
        case .convert: return "convert"
        case .combine: return "combine"
        }
    }

    /// Bump when the generated Automator script logic changes.
    var revision: Int {
        switch self {
        case .convert: return 2
        case .combine: return 1
        }
    }

    var revisionDefaultsKey: String {
        "installedQuickActionRevision.\(rawValue)"
    }
}

enum QuickActionInstaller {
    static var installDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Services", isDirectory: true)
    }

    static func installURL(for kind: QuickActionKind) -> URL {
        installDirectory.appendingPathComponent(kind.workflowFileName)
    }

    static func isInstalled(_ kind: QuickActionKind) -> Bool {
        FileManager.default.fileExists(atPath: installURL(for: kind).path)
    }

    static var allInstalled: Bool {
        QuickActionKind.allCases.allSatisfy(isInstalled)
    }

    static func installIfNeeded() {
        for kind in QuickActionKind.allCases {
            let stored = UserDefaults.standard.integer(forKey: kind.revisionDefaultsKey)
            if !isInstalled(kind) || stored < kind.revision {
                do {
                    try install(kind)
                    UserDefaults.standard.set(kind.revision, forKey: kind.revisionDefaultsKey)
                } catch {
                    // Silent self-heal; Settings can still install manually.
                    NSLog("MarkItDown Quick Action install failed (\(kind.rawValue)): \(error.localizedDescription)")
                }
            }
        }
        NSUpdateDynamicServices()
    }

    static func install(_ kind: QuickActionKind) throws {
        guard let bundledWorkflow = Bundle.main.url(
            forResource: kind.resourceName,
            withExtension: "workflow",
            subdirectory: "QuickAction"
        ) else {
            throw InstallError.missingBundledWorkflow(kind.rawValue)
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: installDirectory, withIntermediateDirectories: true)

        let destination = installURL(for: kind)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: bundledWorkflow, to: destination)
        UserDefaults.standard.set(kind.revision, forKey: kind.revisionDefaultsKey)
        NSUpdateDynamicServices()
    }

    static func installAll() throws {
        for kind in QuickActionKind.allCases {
            try install(kind)
        }
    }

    static func uninstall(_ kind: QuickActionKind) throws {
        let destination = installURL(for: kind)
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.removeItem(at: destination)
        UserDefaults.standard.removeObject(forKey: kind.revisionDefaultsKey)
        NSUpdateDynamicServices()
    }

    static func uninstallAll() throws {
        for kind in QuickActionKind.allCases {
            try uninstall(kind)
        }
    }

    // MARK: - Legacy API used by Settings

    static var isInstalled: Bool { allInstalled }

    static func install() throws { try installAll() }

    static func uninstall() throws { try uninstallAll() }

    enum InstallError: LocalizedError {
        case missingBundledWorkflow(String)

        var errorDescription: String? {
            switch self {
            case .missingBundledWorkflow(let name):
                return "The bundled Finder Quick Action “\(name)” was not found in the app."
            }
        }
    }
}
