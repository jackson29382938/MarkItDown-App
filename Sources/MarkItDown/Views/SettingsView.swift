import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage(AppSettings.revealAfterConversionKey) private var revealAfterConversion = false
    @AppStorage(AppSettings.copyAfterConversionMode) private var autoCopyModeRaw = AutoCopyMode.none.rawValue
    @AppStorage(AppSettings.recentResultsLimitKey) private var recentResultsLimit = 8
    @AppStorage(AppSettings.notifyOnConversionCompleteKey) private var notifyOnConversionComplete = true
    @AppStorage(AppSettings.notifyOnConversionFailureKey) private var notifyOnConversionFailure = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    @State private var launchAtLoginError: String?
    @State private var quickActionMessage: String?
    @State private var quickActionIsError = false

    var body: some View {
        TabView {
            Form {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Toggle("Reveal after conversion", isOn: $revealAfterConversion)

                Picker("Auto-copy after conversion", selection: $autoCopyModeRaw) {
                    ForEach(AutoCopyMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }

                Stepper(value: $recentResultsLimit, in: 1...50) {
                    Text("Keep \(recentResultsLimit) recent results")
                }
                .onChange(of: recentResultsLimit) { _, _ in
                    NotificationCenter.default.post(name: .recentResultsLimitDidChange, object: nil)
                }

                Toggle("Notify when conversion completes", isOn: $notifyOnConversionComplete)
                Toggle("Notify when conversion fails", isOn: $notifyOnConversionFailure)

                LabeledContent(ShortcutKind.togglePanel.title) {
                    ShortcutSettingsView(kind: .togglePanel, model: model)
                }

                LabeledContent(ShortcutKind.chooseFiles.title) {
                    ShortcutSettingsView(kind: .chooseFiles, model: model)
                }

                LabeledContent("Finder Quick Action") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(QuickActionInstaller.isInstalled ? "Installed" : "Not installed")
                            .foregroundStyle(QuickActionInstaller.isInstalled ? .green : .secondary)

                        HStack {
                            Button(QuickActionInstaller.isInstalled ? "Reinstall" : "Install") {
                                installQuickAction()
                            }
                            if QuickActionInstaller.isInstalled {
                                Button("Remove") {
                                    removeQuickAction()
                                }
                            }
                        }
                    }
                }

                if let quickActionMessage {
                    Text(quickActionMessage)
                        .font(.caption)
                        .foregroundStyle(quickActionIsError ? .orange : .secondary)
                }

                Text("After installing, enable the Quick Action in System Settings → Privacy & Security → Extensions → Finder Extensions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .frame(width: 520, height: 520)
        .onAppear {
            launchAtLogin = LaunchAtLoginService.isEnabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            launchAtLoginError = nil
            launchAtLogin = LaunchAtLoginService.isEnabled
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = LaunchAtLoginService.isEnabled
        }
    }

    private func installQuickAction() {
        do {
            try QuickActionInstaller.install()
            quickActionIsError = false
            quickActionMessage = "Finder Quick Action installed to ~/Library/Services."
        } catch {
            quickActionIsError = true
            quickActionMessage = error.localizedDescription
        }
    }

    private func removeQuickAction() {
        do {
            try QuickActionInstaller.uninstall()
            quickActionIsError = false
            quickActionMessage = "Finder Quick Action removed."
        } catch {
            quickActionIsError = true
            quickActionMessage = error.localizedDescription
        }
    }
}
