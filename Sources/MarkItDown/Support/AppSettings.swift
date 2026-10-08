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

enum CombineDestinationMode: String, CaseIterable, Identifiable {
    case alwaysAsk
    case downloads
    case besideFirst
    case customFolder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alwaysAsk:
            return "Always ask (1 / 2 / 3)"
        case .downloads:
            return "Downloads"
        case .besideFirst:
            return "Beside first file"
        case .customFolder:
            return "Custom folder"
        }
    }
}

enum CombineSeparatorStyle: String, CaseIterable, Identifiable {
    case blankLine
    case horizontalRule
    case filenameHeading

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blankLine:
            return "Blank line"
        case .horizontalRule:
            return "Horizontal rule (---)"
        case .filenameHeading:
            return "Heading with filename"
        }
    }
}

enum CombineFinderOrder: String, CaseIterable, Identifiable {
    case selectionOrder
    case alphabetical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selectionOrder:
            return "Finder selection order"
        case .alphabetical:
            return "Alphabetical"
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
    static let watchFolderEnabledKey = "watchFolderEnabled"
    static let watchFolderPathKey = "watchFolderPath"
    static let compactPanelKey = "compactPanel"
    static let panelPlacementKey = "panelPlacement"
    static let panelCustomRegionKey = "panelCustomRegion"

    static let combineDestinationModeKey = "combineDestinationMode"
    static let combineAskDefaultChoiceKey = "combineAskDefaultChoice"
    static let combineCustomFolderPathKey = "combineCustomFolderPath"
    static let combineDefaultFileNameKey = "combineDefaultFileName"
    static let combineSeparatorStyleKey = "combineSeparatorStyle"
    static let combineFinderOrderKey = "combineFinderOrder"
    static let combineWriteIndividualFilesKey = "combineWriteIndividualFiles"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            revealAfterConversionKey: false,
            copyAfterConversionMode: AutoCopyMode.none.rawValue,
            recentResultsLimitKey: 8,
            notifyOnConversionCompleteKey: true,
            notifyOnConversionFailureKey: true,
            watchFolderEnabledKey: false,
            watchFolderPathKey: "",
            compactPanelKey: false,
            panelPlacementKey: PanelPlacement.statusItem.rawValue,
            combineDestinationModeKey: CombineDestinationMode.alwaysAsk.rawValue,
            combineAskDefaultChoiceKey: 1,
            combineCustomFolderPathKey: "",
            combineDefaultFileNameKey: "combined.md",
            combineSeparatorStyleKey: CombineSeparatorStyle.blankLine.rawValue,
            combineFinderOrderKey: CombineFinderOrder.selectionOrder.rawValue,
            combineWriteIndividualFilesKey: false
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

    static var compactPanel: Bool {
        UserDefaults.standard.bool(forKey: compactPanelKey)
    }

    static var panelPlacement: PanelPlacement {
        PanelPlacement(rawValue: UserDefaults.standard.string(forKey: panelPlacementKey) ?? "") ?? .statusItem
    }

    /// The selected screen area in global AppKit coordinates, or nil if none has been selected.
    static var panelCustomRegion: CGRect? {
        guard let data = UserDefaults.standard.data(forKey: panelCustomRegionKey) else { return nil }
        return try? JSONDecoder().decode(CGRect.self, from: data)
    }

    static var notifyOnConversionComplete: Bool {
        UserDefaults.standard.bool(forKey: notifyOnConversionCompleteKey)
    }

    static var notifyOnConversionFailure: Bool {
        UserDefaults.standard.bool(forKey: notifyOnConversionFailureKey)
    }

    static var watchFolderEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: watchFolderEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: watchFolderEnabledKey)
        }
    }

    static var watchFolderURL: URL? {
        get {
            let path = UserDefaults.standard.string(forKey: watchFolderPathKey) ?? ""
            return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            UserDefaults.standard.set(newValue?.path ?? "", forKey: watchFolderPathKey)
        }
    }

    static var combineDestinationMode: CombineDestinationMode {
        get {
            CombineDestinationMode(
                rawValue: UserDefaults.standard.string(forKey: combineDestinationModeKey)
                    ?? CombineDestinationMode.alwaysAsk.rawValue
            ) ?? .alwaysAsk
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: combineDestinationModeKey)
        }
    }

    /// Pre-selected option in the ask dialog: 1 Downloads, 2 Beside first, 3 Custom.
    static var combineAskDefaultChoice: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: combineAskDefaultChoiceKey)
            return (1...3).contains(value) ? value : 1
        }
        set {
            UserDefaults.standard.set(min(max(newValue, 1), 3), forKey: combineAskDefaultChoiceKey)
        }
    }

    static var combineCustomFolderURL: URL? {
        get {
            let path = UserDefaults.standard.string(forKey: combineCustomFolderPathKey) ?? ""
            return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            UserDefaults.standard.set(newValue?.path ?? "", forKey: combineCustomFolderPathKey)
        }
    }

    static var combineDefaultFileName: String {
        get {
            let value = UserDefaults.standard.string(forKey: combineDefaultFileNameKey) ?? "combined.md"
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "combined.md" }
            return trimmed.lowercased().hasSuffix(".md") ? trimmed : "\(trimmed).md"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: combineDefaultFileNameKey)
        }
    }

    static var combineSeparatorStyle: CombineSeparatorStyle {
        get {
            CombineSeparatorStyle(
                rawValue: UserDefaults.standard.string(forKey: combineSeparatorStyleKey)
                    ?? CombineSeparatorStyle.blankLine.rawValue
            ) ?? .blankLine
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: combineSeparatorStyleKey)
        }
    }

    static var combineFinderOrder: CombineFinderOrder {
        get {
            CombineFinderOrder(
                rawValue: UserDefaults.standard.string(forKey: combineFinderOrderKey)
                    ?? CombineFinderOrder.selectionOrder.rawValue
            ) ?? .selectionOrder
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: combineFinderOrderKey)
        }
    }

    static var combineWriteIndividualFiles: Bool {
        get {
            UserDefaults.standard.bool(forKey: combineWriteIndividualFilesKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: combineWriteIndividualFilesKey)
        }
    }
}

extension Notification.Name {
    static let recentResultsLimitDidChange = Notification.Name("recentResultsLimitDidChange")
}
