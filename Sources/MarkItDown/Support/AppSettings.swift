import Foundation

enum AutoCopyMode: String, CaseIterable, Identifiable {
    case none
    case text
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "Don't copy"
        case .text:
            return "Copy markdown text"
        case .file:
            return "Copy markdown file"
        }
    }
}

enum AppSettings {
    static let revealAfterConversionKey = "revealAfterConversion"
    static let copyAfterConversionMode = "copyAfterConversionMode"
    static let legacyCopyAfterConversion = "copyAfterConversion"
    static let recentResultsLimitKey = "recentResultsLimit"
    static let notifyOnConversionCompleteKey = "notifyOnConversionComplete"
    static let notifyOnConversionFailureKey = "notifyOnConversionFailure"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            revealAfterConversionKey: false,
            copyAfterConversionMode: AutoCopyMode.none.rawValue,
            recentResultsLimitKey: 8,
            notifyOnConversionCompleteKey: true,
            notifyOnConversionFailureKey: true
        ])
    }

    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: copyAfterConversionMode) == nil,
           defaults.bool(forKey: legacyCopyAfterConversion) {
            defaults.set(AutoCopyMode.text.rawValue, forKey: copyAfterConversionMode)
        }
    }

    static var autoCopyMode: AutoCopyMode {
        get {
            AutoCopyMode(
                rawValue: UserDefaults.standard.string(forKey: copyAfterConversionMode) ?? AutoCopyMode.none.rawValue
            ) ?? .none
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: copyAfterConversionMode)
        }
    }

    static var recentResultsLimit: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: recentResultsLimitKey)
            return value > 0 ? min(value, 50) : 8
        }
        set {
            UserDefaults.standard.set(min(max(newValue, 1), 50), forKey: recentResultsLimitKey)
        }
    }

    static var revealAfterConversion: Bool {
        UserDefaults.standard.bool(forKey: revealAfterConversionKey)
    }

    static var notifyOnConversionComplete: Bool {
        UserDefaults.standard.bool(forKey: notifyOnConversionCompleteKey)
    }

    static var notifyOnConversionFailure: Bool {
        UserDefaults.standard.bool(forKey: notifyOnConversionFailureKey)
    }
}

extension Notification.Name {
    static let recentResultsLimitDidChange = Notification.Name("recentResultsLimitDidChange")
}
