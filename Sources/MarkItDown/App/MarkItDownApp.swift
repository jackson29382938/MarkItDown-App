import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private let statusItemController: StatusItemController
    private let hotKeyService = HotKeyService()
    private var shortcutObserver: NSObjectProtocol?
    private var recentLimitObserver: NSObjectProtocol?

    override init() {
        ShortcutKind.registerDefaults()
        self.statusItemController = StatusItemController(model: model)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        QuickActionInstaller.installIfNeeded()
        ConversionNotificationService.requestAuthorizationIfNeeded()
        statusItemController.start()
        registerGlobalShortcuts()
        handleIncomingURLs(parseConvertArguments(CommandLine.arguments).map { (.convert, $0) })

        shortcutObserver = NotificationCenter.default.addObserver(
            forName: .globalShortcutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.registerGlobalShortcuts()
                self?.statusItemController.refreshTooltip()
            }
        }

        recentLimitObserver = NotificationCenter.default.addObserver(
            forName: .recentResultsLimitDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.model.trimRecentResultsToLimit()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let shortcutObserver {
            NotificationCenter.default.removeObserver(shortcutObserver)
        }
        if let recentLimitObserver {
            NotificationCenter.default.removeObserver(recentLimitObserver)
        }
        hotKeyService.unregisterAll()
        statusItemController.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        statusItemController.restoreStatusItem()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItemController.restoreAndShowPanel()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let routed = urls.flatMap(routeLaunchURL)
        handleIncomingURLs(routed)
    }

    private func registerGlobalShortcuts() {
        var conflictMessages: [ShortcutKind: String] = [:]
        let duplicateKinds = ShortcutKind.duplicateKinds()

        for kind in duplicateKinds {
            conflictMessages[kind] = "This shortcut is already used by another MarkItDown action."
        }

        let toggleResult = hotKeyService.register(
            shortcut: ShortcutKind.togglePanel.load(),
            action: .togglePanel
        ) { [weak self] in
            self?.statusItemController.togglePanel()
        }
        applyShortcutResult(toggleResult, kind: .togglePanel, into: &conflictMessages)

        let chooseResult = hotKeyService.register(
            shortcut: ShortcutKind.chooseFiles.load(),
            action: .chooseFiles
        ) { [weak self] in
            self?.statusItemController.chooseFilesViaShortcut()
        }
        applyShortcutResult(chooseResult, kind: .chooseFiles, into: &conflictMessages)

        model.updateShortcutConflictMessages(conflictMessages)
    }

    private func applyShortcutResult(
        _ result: HotKeyRegistrationResult,
        kind: ShortcutKind,
        into conflictMessages: inout [ShortcutKind: String]
    ) {
        switch result {
        case .registered:
            break
        case .conflict:
            conflictMessages[kind] = "This shortcut is already used by another app."
        case .failed:
            if conflictMessages[kind] == nil {
                conflictMessages[kind] = "This shortcut could not be registered."
            }
        }
    }

    private enum IncomingAction {
        case convert
        case combine
    }

    private func handleIncomingURLs(_ items: [(IncomingAction, URL)]) {
        guard !items.isEmpty else { return }

        let convertURLs = items.compactMap { $0.0 == .convert ? $0.1 : nil }
        let combineURLs = items.compactMap { $0.0 == .combine ? $0.1 : nil }

        if !convertURLs.isEmpty {
            model.enqueue(urls: convertURLs)
        }
        if !combineURLs.isEmpty {
            model.enqueueCombine(urls: combineURLs)
        }
    }

    private func parseConvertArguments(_ arguments: [String]) -> [URL] {
        var urls: [URL] = []
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--convert" {
                index += 1
                while index < arguments.count, !arguments[index].hasPrefix("-") {
                    urls.append(URL(fileURLWithPath: arguments[index]))
                    index += 1
                }
            } else {
                index += 1
            }
        }
        return urls
    }

    private func routeLaunchURL(_ url: URL) -> [(IncomingAction, URL)] {
        if url.scheme == "markitdown" {
            let host = url.host ?? ""
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let rawPath = components.queryItems?.first(where: { $0.name == "path" })?.value else {
                return []
            }
            let decoded = rawPath.removingPercentEncoding ?? rawPath
            let fileURL = URL(fileURLWithPath: decoded)
            switch host {
            case "combine":
                return [(.combine, fileURL)]
            case "convert":
                return [(.convert, fileURL)]
            default:
                return [(.convert, fileURL)]
            }
        }

        if url.isFileURL {
            return [(.convert, url)]
        }

        return []
    }
}

@main
struct MarkItDownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}
