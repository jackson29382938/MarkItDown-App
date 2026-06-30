import Foundation

enum ConversionJobStatus: String, Codable, Equatable {
    case pending
    case running
    case succeeded
    case failed
}

struct ConversionJob: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    let outputURL: URL
    var status: ConversionJobStatus
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var result: ConversionResult?
    var errorMessage: String?

    init(sourceURL: URL, outputURL: URL) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.status = .pending
        self.createdAt = Date()
    }
}

struct ConversionResult: Identifiable, Codable, Equatable {
    let id: UUID
    let sourceURL: URL
    let markdownURL: URL
    let engineVersion: String
    let elapsedTime: TimeInterval
    let completedAt: Date

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        markdownURL: URL,
        engineVersion: String,
        elapsedTime: TimeInterval,
        completedAt: Date = Date()
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.markdownURL = markdownURL
        self.engineVersion = engineVersion
        self.elapsedTime = elapsedTime
        self.completedAt = completedAt
    }
}
