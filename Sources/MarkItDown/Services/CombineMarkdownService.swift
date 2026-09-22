import Foundation

enum CombineMarkdownService {
    static func separator(between previous: String?, nextFileName: String, style: CombineSeparatorStyle) -> String {
        guard previous != nil else {
            if style == .filenameHeading {
                return "## \(nextFileName)\n\n"
            }
            return ""
        }

        switch style {
        case .blankLine:
            return "\n\n"
        case .horizontalRule:
            return "\n\n---\n\n"
        case .filenameHeading:
            return "\n\n## \(nextFileName)\n\n"
        }
    }

    static func merge(sections: [(fileName: String, markdown: String)], style: CombineSeparatorStyle) -> String {
        var output = ""
        var previous: String?

        for section in sections {
            let body = section.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            output += separator(between: previous, nextFileName: section.fileName, style: style)
            output += body
            previous = body
        }

        if output.isEmpty {
            return ""
        }
        return output.hasSuffix("\n") ? output : output + "\n"
    }

    static func orderedSources(_ urls: [URL], order: CombineFinderOrder) -> [URL] {
        switch order {
        case .selectionOrder:
            return urls
        case .alphabetical:
            return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
    }
}
