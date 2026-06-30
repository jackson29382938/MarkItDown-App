import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.markitdown.menubar",
        category: "MenuBar"
    )
    private let model: AppModel
    private let popover: NSPopover
    private var statusItem: NSStatusItem?
    private var modelObserver: AnyCancellable?
    private var escapeMonitor: Any?
    private var globalEscapeMonitor: Any?
    private var heartbeatTimer: Timer?
    private var workspaceObservers: [(NotificationCenter, NSObjectProtocol)] = []

    init(model: AppModel) {
        self.model = model
        self.popover = NSPopover()
        super.init()
        configurePopover()
        observeModel()
    }

    func start() {
        restoreStatusItem()
        refreshTooltip()
        installRecoveryObservers()
        startHeartbeat()
    }

    func stop() {
        removeEscapeMonitor()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        workspaceObservers.forEach { center, token in
            center.removeObserver(token)
        }
        workspaceObservers.removeAll()
        removeStatusItem()
    }

    func restoreStatusItem() {
        guard statusItem?.button == nil || statusItem?.isVisible == false else {
            updateStatusPresentation()
            return
        }

        recreateStatusItem(reason: "missing or hidden")
    }

    func restoreAndShowPanel() {
        recreateStatusItem(reason: "app reopen")
        showPopover()
    }

    func togglePanel() {
        popover.isShown ? closePopover() : showPopover()
    }

    func chooseFilesViaShortcut() {
        if popover.isShown {
            closePopover()
        }

        NSApp.activate(ignoringOtherApps: true)
        let urls = model.pickFiles()
        guard !urls.isEmpty else { return }

        model.enqueue(urls: urls)
        showPopover()
    }

    func refreshTooltip() {
        let toggle = ShortcutKind.togglePanel.load().displayString
        let choose = ShortcutKind.chooseFiles.load().displayString
        statusItem?.button?.toolTip = "MarkItDown (\(toggle) toggle, \(choose) choose files)"
    }

    private func configureStatusItem(_ item: NSStatusItem) {
        item.isVisible = true
        item.behavior = []
        guard let button = item.button else {
            logger.error("Status item button was unavailable after creation")
            return
        }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.toolTip = "MarkItDown"
        updateStatusPresentation()
        refreshTooltip()
    }

    private func configurePopover() {
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: StatusPanelView(
                model: model,
                openSettings: { [weak self] in self?.openSettings() },
                closePanel: { [weak self] in self?.closePopover() }
            )
        )
    }

    private func observeModel() {
        modelObserver = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusPresentation()
            }
        }
    }

    private func updateStatusPresentation() {
        updateStatusImage()
        updateStatusBadge()
    }

    private func updateStatusBadge() {
        let count = model.activeJobCount
        guard let button = statusItem?.button else { return }

        if count > 0 {
            button.title = "\(count)"
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    private func updateStatusImage() {
        restoreStatusItemIfNeededWithoutRecursing()
        if let brandedImage = brandedStatusImage() {
            statusItem?.button?.image = brandedImage
            return
        }

        let image = NSImage(
            systemSymbolName: model.statusSystemImage,
            accessibilityDescription: "MarkItDown"
        )
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    private func brandedStatusImage() -> NSImage? {
        guard !model.isConverting, !model.hasAttention else {
            return nil
        }
        return BrandImage.menuBarLogo()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePanel()
            return
        }

        if event.type == .rightMouseUp {
            showStatusMenu(from: sender)
        } else {
            togglePanel()
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        togglePanel()
    }

    @objc private func togglePanelFromMenu() {
        togglePanel()
    }

    @objc private func chooseFilesFromMenu() {
        chooseFilesViaShortcut()
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func showStatusMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let toggleItem = NSMenuItem(
            title: "Toggle Panel",
            action: #selector(togglePanelFromMenu),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let chooseItem = NSMenuItem(
            title: "Choose Files…",
            action: #selector(chooseFilesFromMenu),
            keyEquivalent: ""
        )
        chooseItem.target = self
        menu.addItem(chooseItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "Quit MarkItDown",
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 5),
            in: button
        )
    }

    private func showPopover() {
        restoreStatusItem()
        guard let button = statusItem?.button else {
            logger.error("Cannot show panel because the status item button is missing")
            return
        }
        updateStatusPresentation()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        installEscapeMonitor()
    }

    private func closePopover() {
        popover.performClose(nil)
        removeEscapeMonitor()
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func installEscapeMonitor() {
        guard escapeMonitor == nil, globalEscapeMonitor == nil else { return }

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.popover.isShown else { return event }
            self.closePopover()
            return nil
        }

        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.popover.isShown else { return }
            Task { @MainActor in
                self.closePopover()
            }
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        if let globalEscapeMonitor {
            NSEvent.removeMonitor(globalEscapeMonitor)
            self.globalEscapeMonitor = nil
        }
    }

    func popoverDidClose(_ notification: Notification) {
        removeEscapeMonitor()
    }

    private func removeStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    private func recreateStatusItem(reason: String) {
        removeStatusItem()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        configureStatusItem(item)
        logger.notice("Restored MarkItDown status item: \(reason, privacy: .public)")
    }

    private func restoreStatusItemIfNeededWithoutRecursing() {
        guard statusItem == nil || statusItem?.button == nil || statusItem?.isVisible == false else {
            return
        }

        recreateStatusItem(reason: "image update")
    }

    private func installRecoveryObservers() {
        guard workspaceObservers.isEmpty else { return }

        let notificationCenter = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        let screenObserver = notificationCenter.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.restoreStatusItem()
                }
            }
        workspaceObservers.append((notificationCenter, screenObserver))

        let wakeObserver = workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.restoreStatusItem()
                }
            }
        workspaceObservers.append((workspaceCenter, wakeObserver))
    }

    private func startHeartbeat() {
        guard heartbeatTimer == nil else { return }
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.restoreStatusItem()
            }
        }
    }
}
