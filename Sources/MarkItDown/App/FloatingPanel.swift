import AppKit

/// Borderless panel used when the panel is placed in a custom screen area.
/// It must be able to become key so its buttons and Esc handling work.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
