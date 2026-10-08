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
    private let settingsWindowController: SettingsWindowController
    private var statusItem: NSStatusItem?
    private var modelObserver: AnyCancellable?
    private var escapeMonitor: Any?
    private var globalEscapeMonitor: Any?
    private var panelShortcutMonitor: Any?
    private var floatingPanel: FloatingPanel?
    private var floatingHosting: NSHostingController<StatusPanelView>?
    private var heartbeatTimer: Timer?
    private var workspaceObservers: [(NotificationCenter, NSObjectProtocol)] = []

    init(model: AppModel) {
        self.model = model
        self.popover = NSPopover()
        self.settingsWindowController = SettingsWindowController(model: model)
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
        removePanelShortcutMonitor()
        floatingPanel?.orderOut(nil)
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        workspaceObservers.forEach { center, token in
            center.removeObserver(token)
        }
        workspaceObservers.removeAll()
        removeStatusItem()
    }

    func restoreStatusItem() {
        // Recreating the status item removes the button the panel is anchored to,
        // which closes the panel. Defer until it closes (see popoverDidClose).
        guard !popover.isShown else { return }

        guard statusItem?.button == nil || statusItem?.isVisible == false else {
            updateStatusPresentation()
            return
        }

        recreateStatusItem(reason: "missing or hidden")
    }

    func restoreAndShowPanel() {
        recreateStatusItem(reason: "app reopen")
        showPanel()
    }

    func togglePanel() {
        isPanelShown ? closePanel() : showPanel()
    }

    func chooseFilesViaShortcut() {
        if isPanelShown {
            closePanel()
        }

        NSApp.activate(ignoringOtherApps: true)
        let urls = model.pickFiles()
        guard !urls.isEmpty else { return }

        model.enqueue(urls: urls)
        showPanel()
    }

    func refreshTooltip() {
        let toggle = ShortcutKind.togglePanel.load().displayString
        let choose = ShortcutKind.chooseFiles.load().displayString
        statusItem?.button?.toolTip = "MarkItDown (\(toggle) toggle, \(choose) choose)"
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
        popover.contentViewController = NSHostingController(rootView: makePanelRootView())
    }

    private func makePanelRootView() -> StatusPanelView {
        StatusPanelView(
            model: model,
            openSettings: { [weak self] in self?.openSettings() },
            closePanel: { [weak self] in self?.closePanel() }
        )
    }

    private var isPanelShown: Bool {
        floatingPanel?.isVisible == true || popover.isShown
    }

    private var currentPanelWindow: NSWindow? {
        if floatingPanel?.isVisible == true {
            return floatingPanel
        }
        return popover.contentViewController?.view.window
    }

    private func observeModel() {
        modelObserver = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusPresentation()
                self?.refreshFloatingPanelLayout()
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
            title: "Choose Files or Folders…",
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

    private func showPanel() {
        restoreStatusItem()
        updateStatusPresentation()

        if AppSettings.panelPlacement == .customArea, let region = AppSettings.panelCustomRegion {
            showFloatingPanel(in: region)
        } else {
            guard let button = statusItem?.button else {
                logger.error("Cannot show panel because the status item button is missing")
                return
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }

        installEscapeMonitor()
        installPanelShortcutMonitor()
    }

    private func closePanel() {
        popover.performClose(nil)
        floatingPanel?.orderOut(nil)
        removeEscapeMonitor()
        removePanelShortcutMonitor()
        restoreStatusItem()
    }

    private func showFloatingPanel(in region: CGRect) {
        let panel = floatingPanel ?? makeFloatingPanel()
        layoutFloatingPanel(in: region)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makeFloatingPanel() -> FloatingPanel {
        let hosting = NSHostingController(rootView: makePanelRootView())
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Matches the popover's translucent look.
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true

        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])
        panel.contentView = background

        floatingHosting = hosting
        floatingPanel = panel
        return panel
    }

    /// Places the panel inside the selected area, anchored at its top-left corner.
    /// The panel is kept on the visible screen if the area sits near an edge.
    private func layoutFloatingPanel(in region: CGRect) {
        guard let panel = floatingPanel, let hosting = floatingHosting else { return }

        let size = hosting.view.fittingSize
        let screenFrame = NSScreen.screens.first(where: { $0.frame.intersects(region) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? region

        let x = min(max(region.minX, screenFrame.minX), screenFrame.maxX - size.width)
        let y = min(max(region.maxY - size.height, screenFrame.minY), screenFrame.maxY - size.height)
        panel.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    /// Keeps the floating panel's top-left corner fixed while its height changes (for example, when recents grow).
    private func refreshFloatingPanelLayout() {
        guard floatingPanel?.isVisible == true, let region = AppSettings.panelCustomRegion else { return }
        layoutFloatingPanel(in: region)
    }

    /// A local monitor only receives events sent to MarkItDown, so while another app
    /// is active these keys go to that app untouched.
    private func installPanelShortcutMonitor() {
        guard panelShortcutMonitor == nil else { return }

        panelShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handlePanelShortcut(event) else { return event }
            return nil
        }
    }

    private func removePanelShortcutMonitor() {
        if let panelShortcutMonitor {
            NSEvent.removeMonitor(panelShortcutMonitor)
            self.panelShortcutMonitor = nil
        }
    }

    /// Returns true when the event was a recent-file shortcut and was handled.
    private func handlePanelShortcut(_ event: NSEvent) -> Bool {
        guard isPanelShown,
              let panelWindow = currentPanelWindow,
              event.window === panelWindow,
              let match = RecentResultShortcut.match(event),
              match.row < model.recentResults.count else {
            return false
        }

        let result = model.recentResults[match.row]
        switch match.action {
        case .copyText:
            model.copyMarkdownText(result)
        case .copyFile:
            model.copyMarkdownFile(result)
        case .reveal:
            model.reveal(result.markdownURL)
        }
        return true
    }

    private func openSettings() {
        closePanel()
        settingsWindowController.show()
    }

    private func installEscapeMonitor() {
        guard escapeMonitor == nil, globalEscapeMonitor == nil else { return }

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.isPanelShown else { return event }
            self.closePanel()
            return nil
        }

        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.isPanelShown else { return }
            Task { @MainActor in
                self.closePanel()
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
        removePanelShortcutMonitor()
        restoreStatusItem()
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
        guard !popover.isShown else { return }

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
