import SwiftUI
import UniformTypeIdentifiers

struct CombineItem: Identifiable, Equatable {
    let id: UUID
    let url: URL

    init(url: URL) {
        self.id = UUID()
        self.url = url.standardizedFileURL
    }
}

struct CombineDropZoneView: View {
    @Binding var items: [CombineItem]
    let isCombining: Bool
    let onCombine: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                    )
                    .background(.quaternary.opacity(isTargeted ? 0.8 : 0.35), in: RoundedRectangle(cornerRadius: 8))

                if items.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Drop files to combine")
                                .font(.subheadline.weight(.semibold))
                            Text("Reorder below, then Combine")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(14)
                } else {
                    List {
                        ForEach(items) { item in
                            HStack(spacing: 8) {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                                Text(item.url.lastPathComponent)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    items.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .onMove(perform: moveItems)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(maxHeight: min(CGFloat(items.count) * 28 + 8, 140))
                    .padding(.vertical, 4)
                }
            }
            .frame(minHeight: items.isEmpty ? 72 : nil)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
                loadFileURLs(from: providers)
            }

            HStack {
                Text(items.isEmpty ? " " : "\(items.count) file\(items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if !items.isEmpty {
                    Button("Clear") {
                        items.removeAll()
                    }
                    .controlSize(.small)
                }

                Button {
                    onCombine()
                } label: {
                    if isCombining {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Combine")
                    }
                }
                .controlSize(.small)
                .disabled(items.count < 1 || isCombining)
                .keyboardShortcut("m", modifiers: [.command])
            }
        }
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    private func loadFileURLs(from providers: [NSItemProvider]) -> Bool {
        var didRequestFile = false

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            didRequestFile = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let itemURL = item as? URL {
                    url = itemURL
                } else if let data = item as? Data,
                          let string = String(data: data, encoding: .utf8) {
                    url = URL(string: string)
                } else if let string = item as? String {
                    url = URL(string: string)
                } else {
                    url = nil
                }

                if let url {
                    DispatchQueue.main.async {
                        appendUnique(url)
                    }
                }
            }
        }

        return didRequestFile
    }

    private func appendUnique(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard !items.contains(where: { $0.url.path == standardized.path }) else { return }
        items.append(CombineItem(url: standardized))
    }
}
