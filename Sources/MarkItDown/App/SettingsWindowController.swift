import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let window = existingOrNewWindow()
        window.centerIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func existingOrNewWindow() -> NSWindow {
        if let window {
            return window
        }

        let hostingController = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MarkItDown Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 520))
        window.minSize = NSSize(width: 520, height: 520)
        self.window = window
        return window
    }
}

private extension NSWindow {
    func centerIfNeeded() {
        guard !isVisible else { return }
        center()
    }
}
