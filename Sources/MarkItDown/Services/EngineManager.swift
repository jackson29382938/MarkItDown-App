import Foundation

enum EngineManagerError: LocalizedError {
    case resourceDirectoryMissing
    case missingEngine(URL)
    case missingPython(URL)
    case missingWorker(URL)
    case missingManifest(URL)

    var errorDescription: String? {
        switch self {
        case .resourceDirectoryMissing:
            return "The app bundle is missing its resources directory."
        case .missingEngine(let url):
            return "No MarkItDown engine was found at \(url.path)."
        case .missingPython(let url):
            return "The bundled Python executable is missing at \(url.path)."
        case .missingWorker(let url):
            return "The MarkItDown worker script is missing at \(url.path)."
        case .missingManifest(let url):
            return "The engine manifest is missing at \(url.path)."
        }
    }
}

final class EngineManager {
    private let fileManager: FileManager
    private let bundle: Bundle

    init(fileManager: FileManager = .default, bundle: Bundle = .main) {
        self.fileManager = fileManager
        self.bundle = bundle
    }

    func activeEngine() throws -> EngineRuntime {
        let updatedEngine = currentUserEngineURL()
        if fileManager.fileExists(atPath: updatedEngine.path),
           let runtime = try? runtime(at: updatedEngine) {
            return runtime
        }

        return try runtime(at: bundledEngineURL())
    }

    func bundledPythonDirectory() throws -> URL {
        let pythonDirectory = try bundledEngineURL().appendingPathComponent("python")
        let executable = pythonDirectory.appendingPathComponent("bin/python3.12")
        guard fileManager.fileExists(atPath: executable.path) else {
            throw EngineManagerError.missingPython(executable)
        }
        return pythonDirectory
    }

    func appSupportEngineRoot() throws -> URL {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("MarkItDown", isDirectory: true)
        .appendingPathComponent("Engine", isDirectory: true)

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func currentUserEngineURL() -> URL {
        let support = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return support?
            .appendingPathComponent("MarkItDown", isDirectory: true)
            .appendingPathComponent("Engine", isDirectory: true)
            .appendingPathComponent("current", isDirectory: true)
            ?? URL(fileURLWithPath: "/__missing_markitdown_engine__")
    }

    private func runtime(at engineRoot: URL) throws -> EngineRuntime {
        guard fileManager.fileExists(atPath: engineRoot.path) else {
            throw EngineManagerError.missingEngine(engineRoot)
        }

        let python = engineRoot.appendingPathComponent("python/bin/python3.12")
        guard fileManager.fileExists(atPath: python.path) else {
            throw EngineManagerError.missingPython(python)
        }

        let worker = try workerURL()
        guard fileManager.fileExists(atPath: worker.path) else {
            throw EngineManagerError.missingWorker(worker)
        }

        let manifestURL = engineRoot.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw EngineManagerError.missingManifest(manifestURL)
        }

        let manifest = try EngineManifest.load(from: manifestURL)
        return EngineRuntime(
            rootURL: engineRoot,
            pythonURL: python,
            sitePackagesURL: engineRoot.appendingPathComponent("site-packages"),
            workerURL: worker,
            manifest: manifest
        )
    }

    private func bundledEngineURL() throws -> URL {
        guard let resourceURL = bundle.resourceURL else {
            throw EngineManagerError.resourceDirectoryMissing
        }
        return resourceURL.appendingPathComponent("Engine", isDirectory: true)
    }

    private func workerURL() throws -> URL {
        guard let resourceURL = bundle.resourceURL else {
            throw EngineManagerError.resourceDirectoryMissing
        }
        return resourceURL
            .appendingPathComponent("Worker", isDirectory: true)
            .appendingPathComponent("markitdown_worker.py")
    }
}
