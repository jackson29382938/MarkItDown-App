import AppKit
import SwiftUI

struct ShortcutSettingsView: View {
    let kind: ShortcutKind
    @ObservedObject var model: AppModel

    @State private var shortcut: GlobalShortcut
    @State private var isRecording = false
    @State private var recorder: Any?

    init(kind: ShortcutKind, model: AppModel) {
        self.kind = kind
        self.model = model
        _shortcut = State(initialValue: kind.load())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button(shortcutLabel) {
                    beginRecording()
                }
                .buttonStyle(.bordered)
                .help("Click to change the global shortcut")

                Button("Reset") {
                    apply(kind.defaultShortcut)
                }
                .disabled(shortcut == kind.defaultShortcut)
            }

            if let conflictMessage = model.shortcutConflictMessages[kind] {
                Text(conflictMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .globalShortcutDidChange)) { notification in
            guard let changedKind = notification.object as? ShortcutKind,
                  changedKind == kind || notification.object == nil else {
                return
            }
            shortcut = kind.load()
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var shortcutLabel: String {
        isRecording ? "Press new shortcut…" : shortcut.displayString
    }

    private func beginRecording() {
        stopRecording()
        isRecording = true

        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            guard let captured = GlobalShortcut.from(event: event),
                  captured.modifiers != 0 else {
                return nil
            }

            apply(captured)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let recorder {
            NSEvent.removeMonitor(recorder)
            self.recorder = nil
        }
    }

    private func apply(_ newShortcut: GlobalShortcut) {
        shortcut = newShortcut
        kind.save(newShortcut)
    }
}
