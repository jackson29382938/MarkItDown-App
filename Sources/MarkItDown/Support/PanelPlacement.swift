import Foundation

/// Where the panel opens: under the menu bar icon, or inside a user-selected screen area.
enum PanelPlacement: String, CaseIterable {
    case statusItem
    case customArea
}
