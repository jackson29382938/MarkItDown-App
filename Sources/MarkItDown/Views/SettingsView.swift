import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("revealAfterConversion") private var revealAfterConversion = false

    var body: some View {
        TabView {
            Form {
                Toggle("Reveal after conversion", isOn: $revealAfterConversion)

                LabeledContent("Output") {
                    Text("Beside source file")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            Form {
                LabeledContent("MarkItDown") {
                    Text(model.currentEngineVersion)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Install") {
                    Text(model.engineManifest?.installKind.rawValue ?? "Unavailable")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Check for Updates") {
                        model.checkForEngineUpdates()
                    }

                    if case .available = model.updateStatus {
                        Button("Install") {
                            model.installAvailableUpdate()
                        }
                    }
                }

                Text(model.updateStatus.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .tabItem {
                Label("Engine", systemImage: "shippingbox")
            }
        }
        .frame(width: 480, height: 260)
    }
}
