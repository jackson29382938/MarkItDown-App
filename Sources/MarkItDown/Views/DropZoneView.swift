import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let isConverting: Bool
    let onFiles: ([URL]) -> Void
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                )
                .background(.quaternary.opacity(isTargeted ? 0.8 : 0.35), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 10) {
                Image(systemName: isConverting ? "arrow.triangle.2.circlepath" : "square.and.arrow.down")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isConverting ? "Converting" : "Drop Files")
                        .font(.headline)
                    Text("PDF, Office, HTML, data, ZIP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(18)
        }
        .frame(height: 94)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            loadFileURLs(from: providers)
        }
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
                        onFiles([url])
                    }
                }
            }
        }

        return didRequestFile
    }
}
