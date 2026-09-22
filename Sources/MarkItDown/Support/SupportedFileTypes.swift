import Foundation

enum SupportedFileTypes {
    /// Extensions the MarkItDown engine can convert (plus markdown for combine).
    static let convertibleExtensions: Set<String> = [
        "docx", "pptx", "xlsx", "xls", "pdf", "msg",
        "txt", "htm", "html", "csv", "json", "xml"
    ]

    static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd"
    ]

    static var allSupportedExtensions: Set<String> {
        convertibleExtensions.union(markdownExtensions)
    }

    static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    static func isSupported(_ url: URL) -> Bool {
        allSupportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Space-separated list for Automator shell scripts.
    static var shellAllowlist: String {
        allSupportedExtensions.sorted().joined(separator: " ")
    }
}
