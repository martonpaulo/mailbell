import Foundation
import AppKit
import UserNotifications

/// Wraps UNUserNotificationCenter. Clicking a notification opens its Gmail URL.
///
/// Note: UNUserNotificationCenter requires a real app bundle identifier. When run
/// as a bare executable (no bundle), it is unavailable; in that case we skip
/// posting and just log, so development runs do not crash.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let urlKey = "gmailURL"

    private var isBundled: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func requestAuthorization() {
        guard isBundled else {
            Log.info("Notifications unavailable (no app bundle); run the packaged .app for native notifications.")
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                Log.error("Notification authorization error: \(error.localizedDescription)")
            } else {
                Log.info("Notification authorization granted: \(granted)")
            }
        }
    }

    func notify(_ header: MessageHeader, account: String) {
        let url = header.gmailURL(account: account)
        guard isBundled else {
            Log.info("[notify] \(header.from) — \(header.subject) (\(url.absoluteString))")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = header.from
        content.body = header.subject
        content.sound = .default
        content.userInfo = [urlKey: url.absoluteString]

        let request = UNNotificationRequest(
            identifier: "mailbell.\(header.uid)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.error("Failed to post notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let urlString = response.notification.request.content.userInfo[urlKey] as? String,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}
