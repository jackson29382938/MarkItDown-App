import AppKit
import Carbon.HIToolbox
import Foundation

struct GlobalShortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    var carbonModifiers: UInt32 { modifiers }

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyLabel(for: keyCode))
        return parts.joined()
    }

    static func from(event: NSEvent) -> GlobalShortcut? {
        guard let keyCode = UInt32(exactly: event.keyCode),
              keyCode != UInt32(kVK_Shift),
              keyCode != UInt32(kVK_RightShift),
              keyCode != UInt32(kVK_Command),
              keyCode != UInt32(kVK_RightCommand),
              keyCode != UInt32(kVK_Option),
              keyCode != UInt32(kVK_RightOption),
              keyCode != UInt32(kVK_Control),
              keyCode != UInt32(kVK_RightControl),
              keyCode != UInt32(kVK_CapsLock),
              keyCode != UInt32(kVK_Function) else {
            return nil
        }

        return GlobalShortcut(
            keyCode: keyCode,
            modifiers: carbonModifiers(from: event.modifierFlags)
        )
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    private static let keyLabels: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
        UInt32(kVK_Escape): "Escape", UInt32(kVK_Tab): "Tab"
    ]

    private static func keyLabel(for keyCode: UInt32) -> String {
        keyLabels[keyCode] ?? "Key \(keyCode)"
    }
}

enum ShortcutKind: String, CaseIterable, Identifiable {
    case togglePanel
    case chooseFiles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .togglePanel:
            return "Toggle panel"
        case .chooseFiles:
            return "Choose files"
        }
    }

    var defaultShortcut: GlobalShortcut {
        switch self {
        case .togglePanel:
            return GlobalShortcut(
                keyCode: UInt32(kVK_ANSI_M),
                modifiers: UInt32(cmdKey | shiftKey)
            )
        case .chooseFiles:
            return GlobalShortcut(
                keyCode: UInt32(kVK_ANSI_O),
                modifiers: UInt32(cmdKey | shiftKey)
            )
        }
    }

    func load() -> GlobalShortcut {
        let defaults = UserDefaults.standard
        let keyCodeKey = storageKey("KeyCode")
        if defaults.object(forKey: keyCodeKey) == nil, self == .togglePanel,
           defaults.object(forKey: "globalShortcutKeyCode") != nil {
            return GlobalShortcut(
                keyCode: UInt32(defaults.integer(forKey: "globalShortcutKeyCode")),
                modifiers: UInt32(defaults.integer(forKey: "globalShortcutModifiers"))
            )
        }
        guard defaults.object(forKey: keyCodeKey) != nil else {
            return defaultShortcut
        }
        return GlobalShortcut(
            keyCode: UInt32(defaults.integer(forKey: keyCodeKey)),
            modifiers: UInt32(defaults.integer(forKey: storageKey("Modifiers")))
        )
    }

    func save(_ shortcut: GlobalShortcut) {
        let defaults = UserDefaults.standard
        defaults.set(Int(shortcut.keyCode), forKey: storageKey("KeyCode"))
        defaults.set(Int(shortcut.modifiers), forKey: storageKey("Modifiers"))
        NotificationCenter.default.post(name: .globalShortcutDidChange, object: self)
    }

    static func registerDefaults() {
        let defaults = UserDefaults.standard
        for kind in ShortcutKind.allCases {
            let shortcut = kind.defaultShortcut
            defaults.register(defaults: [
                kind.storageKey("KeyCode"): Int(shortcut.keyCode),
                kind.storageKey("Modifiers"): Int(shortcut.modifiers)
            ])
        }
    }

    static func duplicateKinds() -> Set<ShortcutKind> {
        let shortcuts = Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.load()) })
        var duplicates = Set<ShortcutKind>()
        for lhs in allCases {
            for rhs in allCases where lhs.rawValue < rhs.rawValue {
                if shortcuts[lhs] == shortcuts[rhs] {
                    duplicates.insert(lhs)
                    duplicates.insert(rhs)
                }
            }
        }
        return duplicates
    }

    private func storageKey(_ suffix: String) -> String {
        "globalShortcut.\(rawValue).\(suffix)"
    }
}

extension Notification.Name {
    static let globalShortcutDidChange = Notification.Name("globalShortcutDidChange")
}
