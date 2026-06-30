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

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSUpdateDynamicServices()
        ConversionNotificationService.requestAuthorizationIfNeeded()
        statusItemController.start()
        registerGlobalShortcuts()
        handleIncomingFileURLs(parseConvertArguments(CommandLine.arguments))

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
        handleIncomingFileURLs(urls.flatMap(urlsFromLaunchURL))
    }

    @objc func convertToMarkdown(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) -> Bool {
        var urls: [URL] = []
        if let filenames = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            urls = filenames.map { URL(fileURLWithPath: $0) }
        } else if let fileURLs = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            urls = fileURLs
        }
        guard !urls.isEmpty else { return false }
        model.enqueue(urls: urls)
        return true
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
        applyRegistrationResult(toggleResult, for: .togglePanel, into: &conflictMessages)

        let chooseResult = hotKeyService.register(
            shortcut: ShortcutKind.chooseFiles.load(),
            action: .chooseFiles
        ) { [weak self] in
            self?.statusItemController.chooseFilesViaShortcut()
        }
        applyRegistrationResult(chooseResult, for: .chooseFiles, into: &conflictMessages)

        model.updateShortcutConflictMessages(conflictMessages)
    }

    private func applyRegistrationResult(
        _ result: HotKeyRegistrationResult,
        for kind: ShortcutKind,
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

    private func handleIncomingFileURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        model.enqueue(urls: urls)
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

    private func urlsFromLaunchURL(_ url: URL) -> [URL] {
        if url.scheme == "markitdown", url.host == "convert" {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let rawPath = components.queryItems?.first(where: { $0.name == "path" })?.value else {
                return []
            }
            let decoded = rawPath.removingPercentEncoding ?? rawPath
            return [URL(fileURLWithPath: decoded)]
        }

        if url.isFileURL {
            return [url]
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
