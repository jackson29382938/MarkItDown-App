import Foundation

struct EngineManifest: Codable, Equatable {
    enum InstallKind: String, Codable {
        case bundled
        case userInstalled
    }

    let markitdownVersion: String
    let pythonVersion: String
    let createdAt: String
    let installKind: InstallKind

    static func load(from url: URL) throws -> EngineManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(EngineManifest.self, from: data)
    }
}

struct EngineRuntime: Equatable {
    let rootURL: URL
    let pythonURL: URL
    let sitePackagesURL: URL
    let workerURL: URL
    let manifest: EngineManifest
}
