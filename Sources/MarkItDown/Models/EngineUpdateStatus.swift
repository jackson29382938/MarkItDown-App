import Foundation

struct EngineRelease: Codable, Equatable {
    let tagName: String
    let version: String
    let name: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
    }

    init(tagName: String, version: String, name: String, htmlURL: URL) {
        self.tagName = tagName
        self.version = version
        self.name = name
        self.htmlURL = htmlURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(String.self, forKey: .tagName)
        self.tagName = tag
        self.version = SemanticVersion.normalized(tag)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? tag
        self.htmlURL = try container.decode(URL.self, forKey: .htmlURL)
    }
}

enum EngineUpdateStatus: Equatable {
    case idle
    case checking
    case upToDate(current: String)
    case available(EngineRelease)
    case installing(EngineRelease)
    case installed(EngineManifest)
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            return "Engine ready"
        case .checking:
            return "Checking for updates"
        case .upToDate(let current):
            return "Engine \(current) is current"
        case .available(let release):
            return "Engine \(release.version) available"
        case .installing(let release):
            return "Installing \(release.version)"
        case .installed(let manifest):
            return "Installed \(manifest.markitdownVersion)"
        case .failed(let message):
            return message
        }
    }
}
