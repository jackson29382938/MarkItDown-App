import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum CombineDestinationChoice: Int {
    case downloads = 1
    case besideFirst = 2
    case custom = 3
}

@MainActor
enum CombineDestinationPicker {
    // The destination window outlives the continuation body that creates it.
    // Keep its controller alive until the user chooses an option or cancels.
    private static var activeController: CombineDestinationWindowController?

    static func resolveOutputURL(for sourceURLs: [URL]) async -> URL? {
        guard let first = sourceURLs.first else { return nil }

        switch AppSettings.combineDestinationMode {
        case .alwaysAsk:
            guard let choice = await presentChooser() else { return nil }
            switch choice {
            case .downloads, .besideFirst:
                return outputURL(for: choice, firstSource: first)
            case .custom:
                return await chooseCustomSaveURL(
                    defaultDirectory: AppSettings.combineCustomFolderURL
                        ?? first.deletingLastPathComponent()
                )
            }
        case .downloads:
            return outputURL(for: .downloads, firstSource: first)
        case .besideFirst:
            return outputURL(for: .besideFirst, firstSource: first)
        case .customFolder:
            if let folder = AppSettings.combineCustomFolderURL {
                return uniqueFileURL(named: AppSettings.combineDefaultFileName, in: folder)
            }
            return await chooseCustomSaveURL(defaultDirectory: first.deletingLastPathComponent())
        }
    }

    private static func outputURL(for choice: CombineDestinationChoice, firstSource: URL) -> URL? {
        switch choice {
        case .downloads:
            guard let downloads = try? FileManager.default.url(
                for: .downloadsDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ) else {
                return nil
            }
            return uniqueFileURL(named: AppSettings.combineDefaultFileName, in: downloads)
        case .besideFirst:
            return uniqueFileURL(
                named: AppSettings.combineDefaultFileName,
                in: firstSource.deletingLastPathComponent()
            )
        case .custom:
            return nil
        }
    }

    private static func presentChooser() async -> CombineDestinationChoice? {
        await withCheckedContinuation { continuation in
            let controller = CombineDestinationWindowController(
                defaultChoice: CombineDestinationChoice(rawValue: AppSettings.combineAskDefaultChoice) ?? .downloads
            ) { choice in
                activeController = nil
                continuation.resume(returning: choice)
            }
            activeController = controller
            controller.show()
        }
    }

    private static func chooseCustomSaveURL(defaultDirectory: URL) async -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.directoryURL = defaultDirectory
        panel.nameFieldStringValue = AppSettings.combineDefaultFileName
        panel.allowedContentTypes = [.plainText]
        panel.title = "Save Combined Markdown"
        panel.prompt = "Save"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        var finalURL = url
        if finalURL.pathExtension.lowercased() != "md" {
            finalURL = finalURL.appendingPathExtension("md")
        }
        AppSettings.combineCustomFolderURL = finalURL.deletingLastPathComponent()
        return finalURL
    }

    static func uniqueFileURL(named fileName: String, in directory: URL) -> URL {
        let baseName = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension.isEmpty ? "md" : (fileName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
        if !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        var suffix = 2
        repeat {
            candidate = directory
                .appendingPathComponent("\(baseName) \(suffix)")
                .appendingPathExtension(ext)
            suffix += 1
        } while FileManager.default.fileExists(atPath: candidate.path)

        return candidate
    }
}

@MainActor
private final class CombineDestinationWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var keyMonitor: Any?
    private let onComplete: (CombineDestinationChoice?) -> Void
    private let defaultChoice: CombineDestinationChoice
    private var didComplete = false

    init(defaultChoice: CombineDestinationChoice, onComplete: @escaping (CombineDestinationChoice?) -> Void) {
        self.defaultChoice = defaultChoice
        self.onComplete = onComplete
    }

    func show() {
        let root = CombineDestinationDialogView(
            defaultChoice: defaultChoice,
            onChoose: { [weak self] choice in
                self?.finish(with: choice)
            },
            onCancel: { [weak self] in
                self?.finish(with: nil)
            }
        )

        let hosting = NSHostingController(rootView: root)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Combine Markdown"
        panel.contentViewController = hosting
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()
        panel.level = .floating
        panel.hidesOnDeactivate = false

        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.charactersIgnoringModifiers {
            case "1":
                self.finish(with: .downloads)
                return nil
            case "2":
                self.finish(with: .besideFirst)
                return nil
            case "3":
                self.finish(with: .custom)
                return nil
            case "\u{1b}":
                self.finish(with: nil)
                return nil
            default:
                return event
            }
        }
    }

    private func finish(with choice: CombineDestinationChoice?) {
        guard !didComplete else { return }
        didComplete = true

        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        window?.delegate = nil
        window?.close()
        window = nil
        onComplete(choice)
    }

    func windowWillClose(_ notification: Notification) {
        guard !didComplete else { return }
        didComplete = true

        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        window = nil
        onComplete(nil)
    }
}

private struct CombineDestinationDialogView: View {
    let defaultChoice: CombineDestinationChoice
    let onChoose: (CombineDestinationChoice) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where should the combined Markdown go?")
                .font(.headline)

            Text("Press 1, 2, or 3 — or click an option.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                choiceButton(1, title: "Downloads", choice: .downloads)
                choiceButton(2, title: "Beside first file", choice: .besideFirst)
                choiceButton(3, title: "Choose location…", choice: .custom)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func choiceButton(_ number: Int, title: String, choice: CombineDestinationChoice) -> some View {
        Button {
            onChoose(choice)
        } label: {
            HStack {
                Text("\(number)")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .frame(width: 28)
                Text(title)
                Spacer()
                if choice == defaultChoice {
                    Text("Default")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                choice == defaultChoice ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
    }
}
