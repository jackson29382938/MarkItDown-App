import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Keyboard shortcuts for the first nine recent files, most recent first.
/// ⌘n copies the text, ⌥n copies the file, ⌘⌥n reveals it in Finder.
/// These are handled by a local event monitor in StatusItemController, not by
/// SwiftUI key equivalents, so they never reach other apps.
enum RecentResultShortcut {
    static let maxRows = 9

    enum Action {
        case copyText
        case copyFile
        case reveal

        var symbols: String {
            switch self {
            case .copyText: return "⌘"
            case .copyFile: return "⌥"
            case .reveal: return "⌘⌥"
            }
        }
    }

    private static let digitKeyCodes: [UInt16: Int] = [
        UInt16(kVK_ANSI_1): 0, UInt16(kVK_ANSI_2): 1, UInt16(kVK_ANSI_3): 2,
        UInt16(kVK_ANSI_4): 3, UInt16(kVK_ANSI_5): 4, UInt16(kVK_ANSI_6): 5,
        UInt16(kVK_ANSI_7): 6, UInt16(kVK_ANSI_8): 7, UInt16(kVK_ANSI_9): 8
    ]

    /// Maps a key event to an action and row index, requiring exactly the expected modifiers.
    static func match(_ event: NSEvent) -> (action: Action, row: Int)? {
        guard let row = digitKeyCodes[event.keyCode] else { return nil }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch modifiers {
        case [.command]:
            return (.copyText, row)
        case [.option]:
            return (.copyFile, row)
        case [.command, .option]:
            return (.reveal, row)
        default:
            return nil
        }
    }

    static func label(_ action: Action, forRow index: Int) -> String? {
        guard index < maxRows else { return nil }
        return "\(action.symbols)\(index + 1)"
    }
}

struct RecentResultsView: View {
    @ObservedObject var model: AppModel
    var closePanel: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text("⌘1 copy text · ⌥1 copy file · ⌘⌥1 reveal (1–9)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 0) {
                ForEach(Array(model.recentResults.enumerated()), id: \.element.id) { index, result in
                    RecentResultRow(
                        result: result,
                        index: index,
                        model: model,
                        closePanel: closePanel
                    )

                    if result.id != model.recentResults.last?.id {
                        Divider()
                            .padding(.leading, 34)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct RecentResultRow: View {
    let result: ConversionResult
    let index: Int
    @ObservedObject var model: AppModel
    let closePanel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.markdownURL.lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(DateFormatters.relativeString(for: result.completedAt)) · \(String(format: "%.1fs", result.elapsedTime))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Mouse clicks close the panel after copying; keyboard shortcuts keep it open.
            actionButton(.copyText, systemImage: "doc.on.doc", help: "Copy Markdown Text") {
                model.copyMarkdownText(result)
                closePanel()
            }

            actionButton(.copyFile, systemImage: "doc.badge.arrow.up", help: "Copy Markdown File") {
                model.copyMarkdownFile(result)
                closePanel()
            }

            actionButton(.reveal, systemImage: "folder", help: "Reveal") {
                model.reveal(result.markdownURL)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func actionButton(
        _ action: RecentResultShortcut.Action,
        systemImage: String,
        help: String,
        perform: @escaping () -> Void
    ) -> some View {
        let shortcutLabel = RecentResultShortcut.label(action, forRow: index)
        Button(action: perform) {
            VStack(spacing: 1) {
                Image(systemName: systemImage)
                if let shortcutLabel {
                    Text(shortcutLabel)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 34)
        }
        .buttonStyle(.borderless)
        .help(shortcutLabel.map { "\(help) (\($0))" } ?? help)
    }
}
