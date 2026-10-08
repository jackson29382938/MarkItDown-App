import SwiftUI

/// Keyboard shortcuts for the first nine recent files, most recent first.
/// ⌘n copies the text, ⌥n copies the file, ⌘⌥n reveals it in Finder.
enum RecentResultShortcut {
    static let maxRows = 9

    enum Action {
        case copyText
        case copyFile
        case reveal

        var keyModifiers: EventModifiers {
            switch self {
            case .copyText: return .command
            case .copyFile: return .option
            case .reveal: return [.command, .option]
            }
        }

        var symbols: String {
            switch self {
            case .copyText: return "⌘"
            case .copyFile: return "⌥"
            case .reveal: return "⌘⌥"
            }
        }
    }

    static func keyEquivalent(forRow index: Int) -> KeyEquivalent? {
        guard index < maxRows else { return nil }
        return KeyEquivalent(Character(String(index + 1)))
    }

    static func label(_ action: Action, forRow index: Int) -> String? {
        guard index < maxRows else { return nil }
        return "\(action.symbols)\(index + 1)"
    }
}

struct RecentResultsView: View {
    @ObservedObject var model: AppModel

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
                    RecentResultRow(result: result, index: index, model: model)

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

            actionButton(.copyText, systemImage: "doc.on.doc", help: "Copy Markdown Text") {
                model.copyMarkdownText(result)
            }

            actionButton(.copyFile, systemImage: "doc.badge.arrow.up", help: "Copy Markdown File") {
                model.copyMarkdownFile(result)
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
        let button = Button(action: perform) {
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

        if let key = RecentResultShortcut.keyEquivalent(forRow: index) {
            button.keyboardShortcut(key, modifiers: action.keyModifiers)
        } else {
            button
        }
    }
}
