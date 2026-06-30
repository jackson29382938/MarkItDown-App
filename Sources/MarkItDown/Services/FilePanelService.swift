import AppKit
import Foundation

struct FilePanelService {
    @MainActor
    func chooseFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.prompt = "Convert"
        return panel.runModal() == .OK ? panel.urls : []
    }
}
