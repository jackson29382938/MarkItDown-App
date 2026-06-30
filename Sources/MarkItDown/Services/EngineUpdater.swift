import Foundation

enum EngineUpdaterError: LocalizedError {
    case invalidVersion
    case installerFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidVersion:
            return "The selected MarkItDown release has no usable version."
        case .installerFailed(let message):
            return message.isEmpty ? "The engine installer failed." : message
        }
    }
}

final class EngineUpdater {
    private let engineManager: EngineManager
    private let fileManager: FileManager
    private let latestReleaseURL = URL(string: "https://api.github.com/repos/microsoft/markitdown/releases/latest")!

    init(engineManager: EngineManager, fileManager: FileManager = .default) {
        self.engineManager = engineManager
        self.fileManager = fileManager
    }

    func latestReleaseCompared(to currentVersion: String) async throws -> EngineUpdateStatus {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("MarkItDown-macOS", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)
        let release = try JSONDecoder().decode(EngineRelease.self, from: data)

        if SemanticVersion(currentVersion) < SemanticVersion(release.version) {
            return .available(release)
        }
        return .upToDate(current: currentVersion)
    }

    func install(release: EngineRelease) async throws -> EngineManifest {
        guard !release.version.isEmpty else {
            throw EngineUpdaterError.invalidVersion
        }

        return try await Task.detached(priority: .userInitiated) {
            let supportRoot = try self.engineManager.appSupportEngineRoot()
            let temporaryRoot = supportRoot.appendingPathComponent("installing-\(UUID().uuidString)", isDirectory: true)
            let currentRoot = supportRoot.appendingPathComponent("current", isDirectory: true)
            let pythonDestination = temporaryRoot.appendingPathComponent("python", isDirectory: true)
            let sitePackages = temporaryRoot.appendingPathComponent("site-packages", isDirectory: true)
            let manifestURL = temporaryRoot.appendingPathComponent("manifest.json")

            try self.fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
            try self.fileManager.copyItem(at: self.engineManager.bundledPythonDirectory(), to: pythonDestination)
            try self.fileManager.createDirectory(at: sitePackages, withIntermediateDirectories: true)

            let python = pythonDestination.appendingPathComponent("bin/python3.12")
            let requirement = "markitdown[docx,pptx,xlsx,xls,pdf,outlook]==\(release.version)"
            let installOutput = try self.runInstaller(
                python: python,
                arguments: [
                    "-m", "pip", "install",
                    "--disable-pip-version-check",
                    "--no-input",
                    "--upgrade",
                    "--target", sitePackages.path,
                    requirement
                ]
            )

            guard installOutput.exitCode == 0 else {
                try? self.fileManager.removeItem(at: temporaryRoot)
                throw EngineUpdaterError.installerFailed(installOutput.message)
            }

            let manifest = EngineManifest(
                markitdownVersion: release.version,
                pythonVersion: "3.12",
                createdAt: ISO8601DateFormatter().string(from: Date()),
                installKind: .userInstalled
            )
            let manifestData = try JSONEncoder().encode(manifest)
            try manifestData.write(to: manifestURL, options: .atomic)

            if self.fileManager.fileExists(atPath: currentRoot.path) {
                try self.fileManager.removeItem(at: currentRoot)
            }
            try self.fileManager.moveItem(at: temporaryRoot, to: currentRoot)
            return manifest
        }
        .value
    }

    private func runInstaller(python: URL, arguments: [String]) throws -> (exitCode: Int32, message: String) {
        let process = Process()
        process.executableURL = python
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["PIP_DISABLE_PIP_VERSION_CHECK"] = "1"
        environment["PYTHONNOUSERSITE"] = "1"
        process.environment = environment

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: outputData + errorData, encoding: .utf8) ?? ""
        return (process.terminationStatus, message)
    }
}
