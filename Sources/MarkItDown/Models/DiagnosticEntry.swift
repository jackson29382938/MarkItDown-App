import Foundation

struct DiagnosticEntry: Identifiable, Equatable {
    let id: UUID
    let title: String
    let message: String
    let details: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        message: String,
        details: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.details = details
        self.createdAt = createdAt
    }

    var formatted: String {
        """
        [\(ISO8601DateFormatter().string(from: createdAt))] \(title)
        Message: \(message)

        \(details)
        """
    }
}
