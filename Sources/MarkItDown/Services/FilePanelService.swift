import AppKit
import Foundation

struct FilePanelService {
    @MainActor
    func chooseFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.prompt = "Convert"
        return panel.runModal() == .OK ? panel.urls : []
    }

    @MainActor
    func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.prompt = "Watch"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
