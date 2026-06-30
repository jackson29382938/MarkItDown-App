import SwiftUI

struct RecentResultsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(model.recentResults) { result in
                    RecentResultRow(result: result, model: model)

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

            Button {
                model.copyMarkdownText(result)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy Markdown Text")

            Button {
                model.copyMarkdownFile(result)
            } label: {
                Image(systemName: "doc.badge.arrow.up")
            }
            .buttonStyle(.borderless)
            .help("Copy Markdown File")

            Button {
                model.reveal(result.markdownURL)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
