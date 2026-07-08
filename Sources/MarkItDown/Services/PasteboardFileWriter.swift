import AppKit
import Foundation

enum PasteboardFileWriter {
    static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    @discardableResult
    static func copyFile(_ fileURL: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        let standardizedURL = fileURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedURL.path) else {
            return false
        }

        pasteboard.declareTypes([.fileURL, filenamesType], owner: nil)
        let wroteFileURL = pasteboard.setString(standardizedURL.absoluteString, forType: .fileURL)
        let wroteFilenames = pasteboard.setPropertyList([standardizedURL.path], forType: filenamesType)
        return wroteFileURL && wroteFilenames
    }
}
