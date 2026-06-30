import Carbon.HIToolbox
import Foundation
import OSLog

enum HotKeyAction: UInt32 {
    case togglePanel = 1
    case chooseFiles = 2

    var shortcutKind: ShortcutKind {
        switch self {
        case .togglePanel:
            return .togglePanel
        case .chooseFiles:
            return .chooseFiles
        }
    }
}

enum HotKeyRegistrationResult: Equatable {
    case registered
    case conflict
    case failed
}

@MainActor
final class HotKeyService {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.markitdown.menubar",
        category: "HotKey"
    )
    private var hotKeyRefs: [HotKeyAction: EventHotKeyRef] = [:]
    private var handlers: [HotKeyAction: () -> Void] = [:]

    private static let hotKeySignature = OSType(0x4D495444)
    private static var handlerInstalled = false
    private static weak var activeService: HotKeyService?

    @discardableResult
    func register(
        shortcut: GlobalShortcut,
        action: HotKeyAction,
        handler: @escaping () -> Void
    ) -> HotKeyRegistrationResult {
        Self.activeService = self
        unregister(action: action)
        handlers[action] = handler
        installHandlerIfNeeded()

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: action.rawValue)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        switch status {
        case noErr:
            hotKeyRefs[action] = hotKeyRef
            logger.notice(
                "Registered \(action.shortcutKind.title, privacy: .public) shortcut \(shortcut.displayString, privacy: .public)"
            )
            return .registered
        case OSStatus(eventHotKeyExistsErr):
            logger.error(
                "Shortcut conflict for \(action.shortcutKind.title, privacy: .public): \(shortcut.displayString, privacy: .public)"
            )
            return .conflict
        default:
            logger.error(
                "Failed to register \(action.shortcutKind.title, privacy: .public) shortcut: \(status)"
            )
            return .failed
        }
    }

    func unregister(action: HotKeyAction) {
        if let hotKeyRef = hotKeyRefs.removeValue(forKey: action) {
            UnregisterEventHotKey(hotKeyRef)
        }
        handlers.removeValue(forKey: action)
    }

    func unregisterAll() {
        for action in Array(hotKeyRefs.keys) {
            unregister(action: action)
        }
    }

    private func installHandlerIfNeeded() {
        guard !Self.handlerInstalled else { return }
        Self.handlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      hotKeyID.signature == HotKeyService.hotKeySignature,
                      let action = HotKeyAction(rawValue: hotKeyID.id) else {
                    return OSStatus(eventNotHandledErr)
                }

                DispatchQueue.main.async {
                    HotKeyService.activeService?.handlers[action]?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }
}
