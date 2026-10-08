import AppKit

/// Shows a dimmed overlay on every screen so the user can drag out the area where the panel should open.
/// Completion receives the selected rectangle in global AppKit coordinates, or nil when cancelled.
@MainActor
final class PanelAreaSelector {
    static let shared = PanelAreaSelector()

    private var overlays: [NSWindow] = []
    private var completion: ((CGRect?) -> Void)?

    func begin(completion: @escaping (CGRect?) -> Void) {
        finish(nil)
        self.completion = completion

        for screen in NSScreen.screens {
            let window = SelectionWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isReleasedWhenClosed = false

            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { [weak self] rect in self?.finish(rect) }
            view.onCancel = { [weak self] in self?.finish(nil) }
            window.contentView = view
            overlays.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        for window in overlays {
            window.makeKeyAndOrderFront(nil)
        }
        if let first = overlays.first, let view = first.contentView {
            first.makeFirstResponder(view)
        }
    }

    fileprivate func finish(_ rect: CGRect?) {
        let done = completion
        completion = nil
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        NSCursor.arrow.set()
        done?(rect)
    }
}

private final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
private final class SelectionView: NSView {
    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var dragStart: CGPoint?
    private var selection: CGRect?
    private let minimumSize: CGFloat = 40

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        if let selection {
            NSColor.clear.setFill()
            selection.fill(using: .copy)

            let outline = NSBezierPath(rect: selection.insetBy(dx: 1, dy: 1))
            outline.lineWidth = 2
            NSColor.controlAccentColor.setStroke()
            outline.stroke()
        }

        drawHint()
    }

    private func drawHint() {
        let text = "Drag to choose where the panel opens · Esc to cancel" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let origin = NSPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - 80)
        text.draw(at: origin, withAttributes: attributes)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let current = convert(event.locationInWindow, from: nil)
        selection = CGRect(
            x: min(dragStart.x, current.x),
            y: min(dragStart.y, current.y),
            width: abs(current.x - dragStart.x),
            height: abs(current.y - dragStart.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        guard let selection, selection.width >= minimumSize, selection.height >= minimumSize,
              let window else {
            self.selection = nil
            needsDisplay = true
            return
        }

        let screenRect = window.convertToScreen(convert(selection, to: nil))
        onFinish?(screenRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}
