import AppKit
import SwiftUI

struct StatusPanelView: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void

    init(model: AppModel, openSettings: @escaping () -> Void = {}) {
        self.model = model
        self.openSettings = openSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            DropZoneView(isConverting: model.isConverting) { urls in
                model.enqueue(urls: urls)
            }

            actionRow

            if let runningJob = model.jobs.first(where: { $0.status == .running }) {
                RunningJobView(job: runningJob)
            }

            if !model.recentResults.isEmpty {
                RecentResultsView(model: model)
            }

            if let latestDiagnostic = model.latestDiagnostic {
                DebugInfoView(entry: latestDiagnostic, model: model)
            }

            Divider()
            updateRow
        }
        .padding(16)
        .frame(width: 420)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.statusSystemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(model.hasAttention ? Color.orange : Color.accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("MarkItDown")
                    .font(.headline)
                Text("Engine \(model.currentEngineVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.refreshEngineState()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh engine")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                model.chooseFiles()
            } label: {
                Label("Choose Files", systemImage: "plus")
            }
            .keyboardShortcut("o")

            if let latest = model.recentResults.first {
                Button {
                    model.reveal(latest.markdownURL)
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
            }

            Spacer()

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit")
        }
    }

    private var updateRow: some View {
        HStack(spacing: 8) {
            Image(systemName: updateIcon)
                .foregroundStyle(updateColor)
                .frame(width: 18)

            Text(model.updateStatus.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer()

            switch model.updateStatus {
            case .available:
                Button("Install") {
                    model.installAvailableUpdate()
                }
                .controlSize(.small)
            case .checking, .installing:
                ProgressView()
                    .controlSize(.small)
            default:
                Button("Check") {
                    model.checkForEngineUpdates()
                }
                .controlSize(.small)
            }
        }
    }

    private var updateIcon: String {
        switch model.updateStatus {
        case .failed:
            return "exclamationmark.triangle"
        case .available:
            return "arrow.down.circle"
        case .installed, .upToDate:
            return "checkmark.circle"
        case .checking, .installing:
            return "clock"
        case .idle:
            return "shippingbox"
        }
    }

    private var updateColor: Color {
        switch model.updateStatus {
        case .failed:
            return .orange
        case .available:
            return .accentColor
        case .installed, .upToDate:
            return .green
        default:
            return .secondary
        }
    }
}

private struct RunningJobView: View {
    let job: ConversionJob

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.sourceURL.lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(job.outputURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatusMessageView: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DebugInfoView: View {
    let entry: DiagnosticEntry
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                    Text(entry.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    model.copyLatestDebugInfo()
                } label: {
                    Label("Copy Debug", systemImage: "doc.on.doc")
                }
                .controlSize(.small)

                Button {
                    model.revealDebugLog()
                } label: {
                    Label("Reveal Log", systemImage: "folder")
                }
                .controlSize(.small)

                Spacer()

                Button {
                    model.clearDiagnostics()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Clear")
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
