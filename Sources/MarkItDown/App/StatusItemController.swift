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
        installRecoveryObservers()
        startHeartbeat()
    }

    func stop() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
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
            updateStatusImage()
            return
        }

        recreateStatusItem(reason: "missing or hidden")
    }

    func restoreAndShowPanel() {
        recreateStatusItem(reason: "app reopen")
        showPopover()
    }

    private func configureStatusItem(_ item: NSStatusItem) {
        item.isVisible = true
        item.behavior = []
        guard let button = item.button else {
            logger.error("Status item button was unavailable after creation")
            return
        }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.imagePosition = .imageOnly
        button.toolTip = "MarkItDown"
        updateStatusImage()
    }

    private func configurePopover() {
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: StatusPanelView(
                model: model,
                openSettings: { [weak self] in self?.openSettings() }
            )
        )
    }

    private func observeModel() {
        modelObserver = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusImage()
            }
        }
    }

    private func updateStatusImage() {
        restoreStatusItemIfNeededWithoutRecursing()
        let image = NSImage(
            systemSymbolName: model.statusSystemImage,
            accessibilityDescription: "MarkItDown"
        )
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    @objc private func togglePopover(_ sender: Any?) {
        popover.isShown ? closePopover() : showPopover()
    }

    private func showPopover() {
        restoreStatusItem()
        guard let button = statusItem?.button else {
            logger.error("Cannot show panel because the status item button is missing")
            return
        }
        updateStatusImage()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
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
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.keyCode == 53 else { return event }

            let popoverWindow = self.popover.contentViewController?.view.window
            if event.window == popoverWindow || NSApp.keyWindow == popoverWindow {
                self.closePopover()
                return nil
            }

            return event
        }
    }

    private func removeEscapeMonitor() {
        guard let escapeMonitor else { return }
        NSEvent.removeMonitor(escapeMonitor)
        self.escapeMonitor = nil
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
