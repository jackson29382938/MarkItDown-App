import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage(AppSettings.revealAfterConversionKey) private var revealAfterConversion = false
    @AppStorage(AppSettings.compactPanelKey) private var compactPanel = false
    @AppStorage(AppSettings.panelPlacementKey) private var panelPlacementRaw = PanelPlacement.statusItem.rawValue
    @AppStorage(AppSettings.panelCustomRegionKey) private var panelRegionData = Data()
    @AppStorage(AppSettings.copyAfterConversionMode) private var autoCopyModeRaw = AutoCopyMode.none.rawValue
    @AppStorage(AppSettings.recentResultsLimitKey) private var recentResultsLimit = 8
    @AppStorage(AppSettings.notifyOnConversionCompleteKey) private var notifyOnConversionComplete = true
    @AppStorage(AppSettings.notifyOnConversionFailureKey) private var notifyOnConversionFailure = true
    @AppStorage(AppSettings.watchFolderEnabledKey) private var watchFolderEnabled = false
    @AppStorage(AppSettings.combineDestinationModeKey) private var combineDestinationModeRaw = CombineDestinationMode.alwaysAsk.rawValue
    @AppStorage(AppSettings.combineAskDefaultChoiceKey) private var combineAskDefaultChoice = 1
    @AppStorage(AppSettings.combineDefaultFileNameKey) private var combineDefaultFileName = "combined.md"
    @AppStorage(AppSettings.combineSeparatorStyleKey) private var combineSeparatorStyleRaw = CombineSeparatorStyle.blankLine.rawValue
    @AppStorage(AppSettings.combineFinderOrderKey) private var combineFinderOrderRaw = CombineFinderOrder.selectionOrder.rawValue
    @AppStorage(AppSettings.combineWriteIndividualFilesKey) private var combineWriteIndividualFiles = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    @State private var launchAtLoginError: String?
    @State private var quickActionMessage: String?
    @State private var quickActionIsError = false

    var body: some View {
        TabView {
            generalTab
            combineTab
            engineTab
        }
        .frame(width: 540, height: 560)
        .onAppear {
            launchAtLogin = LaunchAtLoginService.isEnabled
        }
    }

    private var panelRegionDescription: String {
        guard let rect = try? JSONDecoder().decode(CGRect.self, from: panelRegionData) else {
            return "Not selected"
        }
        return "\(Int(rect.width)) × \(Int(rect.height)) at \(Int(rect.minX)), \(Int(rect.minY))"
    }

    private var generalTab: some View {
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

            Toggle("Compact panel", isOn: $compactPanel)
            Text("Shows only the drop areas, recent files and Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Panel position", selection: $panelPlacementRaw) {
                Text("Under menu bar icon").tag(PanelPlacement.statusItem.rawValue)
                Text("Custom area of screen").tag(PanelPlacement.customArea.rawValue)
            }

            if panelPlacementRaw == PanelPlacement.customArea.rawValue {
                LabeledContent("Area") {
                    HStack {
                        Text(panelRegionDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Select…") {
                            PanelAreaSelector.shared.begin { rect in
                                guard let rect,
                                      let data = try? JSONEncoder().encode(rect) else { return }
                                panelRegionData = data
                            }
                        }
                        .controlSize(.small)
                    }
                }

                Text("Drag a rectangle on the screen. The panel opens inside it, from its top-left corner. Without a selected area, the panel opens under the menu bar icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

            LabeledContent("Watch Folder") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enabled", isOn: $watchFolderEnabled)
                        .onChange(of: watchFolderEnabled) { _, enabled in
                            model.setWatchFolderEnabled(enabled)
                        }

                    Text(model.watchedFolderURL?.path ?? "No folder selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)

                    HStack {
                        Button {
                            model.chooseWatchFolder()
                        } label: {
                            Label(model.watchedFolderURL == nil ? "Choose" : "Change", systemImage: "folder.badge.plus")
                        }

                        if let watchedFolderURL = model.watchedFolderURL {
                            Button {
                                model.reveal(watchedFolderURL)
                            } label: {
                                Label("Reveal", systemImage: "folder")
                            }

                            Button {
                                model.clearWatchFolder()
                            } label: {
                                Label("Clear", systemImage: "xmark.circle")
                            }
                        }
                    }

                    if let watchFolderError = model.watchFolderError {
                        Text(watchFolderError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            LabeledContent(ShortcutKind.togglePanel.title) {
                ShortcutSettingsView(kind: .togglePanel, model: model)
            }

            LabeledContent(ShortcutKind.chooseFiles.title) {
                ShortcutSettingsView(kind: .chooseFiles, model: model)
            }

            LabeledContent("Finder Quick Actions") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(quickActionStatusText)
                        .foregroundStyle(QuickActionInstaller.allInstalled ? .green : .secondary)

                    HStack {
                        Button(QuickActionInstaller.allInstalled ? "Reinstall" : "Install") {
                            installQuickAction()
                        }
                        if QuickActionInstaller.isInstalled(QuickActionKind.convert)
                            || QuickActionInstaller.isInstalled(QuickActionKind.combine) {
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

            Text("MarkItDown installs Convert and Combine Quick Actions automatically. If they don’t appear in Finder, enable them once in System Settings → Privacy & Security → Extensions → Finder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .tabItem {
            Label("General", systemImage: "gearshape")
        }
    }

    private var combineTab: some View {
        Form {
            Picker("Destination", selection: $combineDestinationModeRaw) {
                ForEach(CombineDestinationMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }

            if combineDestinationModeRaw == CombineDestinationMode.alwaysAsk.rawValue {
                Picker("Ask dialog default", selection: $combineAskDefaultChoice) {
                    Text("1 · Downloads").tag(1)
                    Text("2 · Beside first file").tag(2)
                    Text("3 · Choose location").tag(3)
                }
            }

            if combineDestinationModeRaw == CombineDestinationMode.customFolder.rawValue {
                LabeledContent("Custom folder") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppSettings.combineCustomFolderURL?.path ?? "Not set — you’ll be asked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        Button("Choose Folder…") {
                            chooseCombineFolder()
                        }
                    }
                }
            }

            TextField("Default file name", text: $combineDefaultFileName)

            Picker("Separator between files", selection: $combineSeparatorStyleRaw) {
                ForEach(CombineSeparatorStyle.allCases) { style in
                    Text(style.title).tag(style.rawValue)
                }
            }

            Picker("Finder right-click order", selection: $combineFinderOrderRaw) {
                ForEach(CombineFinderOrder.allCases) { order in
                    Text(order.title).tag(order.rawValue)
                }
            }

            Toggle("Also write individual Markdown files", isOn: $combineWriteIndividualFiles)

            Text("Drag-area order is always the list order (reorderable). Finder Quick Action uses the order setting above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .tabItem {
            Label("Combine", systemImage: "rectangle.stack")
        }
    }

    private var engineTab: some View {
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

    private var quickActionStatusText: String {
        let convert = QuickActionInstaller.isInstalled(.convert)
        let combine = QuickActionInstaller.isInstalled(.combine)
        switch (convert, combine) {
        case (true, true):
            return "Convert + Combine installed"
        case (true, false):
            return "Convert installed · Combine missing"
        case (false, true):
            return "Combine installed · Convert missing"
        case (false, false):
            return "Not installed"
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
            quickActionMessage = "Finder Quick Actions installed to ~/Library/Services."
        } catch {
            quickActionIsError = true
            quickActionMessage = error.localizedDescription
        }
    }

    private func removeQuickAction() {
        do {
            try QuickActionInstaller.uninstall()
            quickActionIsError = false
            quickActionMessage = "Finder Quick Actions removed."
        } catch {
            quickActionIsError = true
            quickActionMessage = error.localizedDescription
        }
    }

    private func chooseCombineFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            AppSettings.combineCustomFolderURL = url
        }
    }
}
