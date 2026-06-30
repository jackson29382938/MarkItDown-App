import Foundation
import UserNotifications

@MainActor
enum ConversionNotificationService {
    private static let center = UNUserNotificationCenter.current()

    static func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyConversionSucceeded(_ result: ConversionResult) {
        guard AppSettings.notifyOnConversionComplete else { return }
        post(
            title: "Conversion complete",
            body: result.markdownURL.lastPathComponent,
            identifier: "conversion.success.\(result.id.uuidString)"
        )
    }

    static func notifyConversionFailed(fileName: String, message: String) {
        guard AppSettings.notifyOnConversionFailure else { return }
        post(
            title: "Conversion failed",
            body: "\(fileName): \(message)",
            identifier: "conversion.failure.\(UUID().uuidString)"
        )
    }

    private static func post(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}
