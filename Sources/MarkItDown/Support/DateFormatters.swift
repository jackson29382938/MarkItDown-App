import Foundation

enum DateFormatters {
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func relativeString(for date: Date) -> String {
        relative.localizedString(for: date, relativeTo: Date())
    }
}
