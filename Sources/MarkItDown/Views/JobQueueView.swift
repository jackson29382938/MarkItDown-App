import SwiftUI

struct JobQueueView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Queue")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(model.queueJobs) { job in
                    JobQueueRow(job: job, model: model)

                    if job.id != model.queueJobs.last?.id {
                        Divider()
                            .padding(.leading, 34)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct JobQueueRow: View {
    let job: ConversionJob
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Group {
                switch job.status {
                case .pending:
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                case .running:
                    ProgressView()
                        .controlSize(.small)
                case .failed:
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                case .succeeded:
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.sourceURL.lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if job.status == .failed {
                Button("Retry") {
                    model.retryJob(job)
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var subtitle: String {
        switch job.status {
        case .pending:
            return "Waiting · \(job.outputURL.lastPathComponent)"
        case .running:
            return "Converting · \(job.outputURL.lastPathComponent)"
        case .failed:
            return job.errorMessage ?? "Conversion failed"
        case .succeeded:
            return job.outputURL.lastPathComponent
        }
    }
}
