import AppKit
import Foundation
@preconcurrency import UserNotifications

private let notificationWebmailURLKey = "webmailURL"
private let notificationAccountIDKey = "accountID"

struct NotificationAuthorizationState {
    let isBundled: Bool
    let status: UNAuthorizationStatus
    let alertSetting: UNNotificationSetting
    let soundSetting: UNNotificationSetting
    let badgeSetting: UNNotificationSetting

    static let unbundled = NotificationAuthorizationState(
        isBundled: false,
        status: .notDetermined,
        alertSetting: .notSupported,
        soundSetting: .notSupported,
        badgeSetting: .notSupported
    )

    var canPostAlert: Bool {
        guard isBundled else { return false }
        guard status == .authorized || status == .provisional else { return false }
        return alertSetting == .enabled || alertSetting == .notSupported
    }

    var summary: String {
        guard isBundled else { return "Unavailable outside app bundle" }
        return status.mailbellDescription
    }

    var detail: String {
        guard isBundled else {
            return "Install and run Mailbell.app to use macOS notifications."
        }
        if status == .denied {
            return "Enable Mailbell in System Settings > Notifications."
        }
        if status == .notDetermined {
            return "Notification permission has not been requested yet."
        }
        if !canPostAlert {
            return "Notification alerts are disabled for Mailbell."
        }
        return "Alerts: \(alertSetting.mailbellDescription), Sound: \(soundSetting.mailbellDescription)"
    }
}

enum NotificationPostResult {
    case posted
    case unavailable(String)
    case notAuthorized(NotificationAuthorizationState)
    case failed(String)

    var userMessage: String? {
        switch self {
        case .posted:
            return nil
        case let .unavailable(message):
            return message
        case let .notAuthorized(state):
            return state.detail
        case let .failed(message):
            return message
        }
    }
}

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    var webmailOpenHandler: (@MainActor (UUID?, URL) async -> Void)?

    private let notificationCenter = UNUserNotificationCenter.current()

    private var isBundled: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    override private init() {
        super.init()
        if isBundled {
            notificationCenter.delegate = self
        }
    }

    func authorizationState() async -> NotificationAuthorizationState {
        guard isBundled else { return .unbundled }
        let settings = await notificationCenter.notificationSettings()
        return NotificationAuthorizationState(
            isBundled: true,
            status: settings.authorizationStatus,
            alertSetting: settings.alertSetting,
            soundSetting: settings.soundSetting,
            badgeSetting: settings.badgeSetting
        )
    }

    func requestAuthorization() async -> NotificationAuthorizationState {
        guard isBundled else {
            Log.info("Notifications unavailable (no app bundle); run the packaged .app for native notifications.")
            return .unbundled
        }
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            Log.info("Notification authorization granted: \(granted)")
        } catch {
            Log.error("Notification authorization error: \(error.localizedDescription)")
        }
        return await authorizationState()
    }

    func requestAuthorizationIfNeeded() async -> NotificationAuthorizationState {
        let state = await authorizationState()
        guard state.status == .notDetermined else { return state }
        return await requestAuthorization()
    }

    func notify(_ header: MessageHeader, account: MailAccount) async -> NotificationPostResult {
        let provider = MailProviderRegistry.provider(for: account.providerID)
        let url = provider.webmailURL
        guard isBundled else {
            let message = "[notify] \(account.email) \(header.from) - \(header.subject) (\(url.absoluteString))"
            Log.info(message)
            return .unavailable("Notifications unavailable outside app bundle.")
        }

        let state = await requestAuthorizationIfNeeded()
        guard state.canPostAlert else {
            let message = state.detail
            Log.error("Notification skipped: \(message)")
            return .notAuthorized(state)
        }

        let content = UNMutableNotificationContent()
        content.title = header.from
        content.body = header.subject
        content.subtitle = account.email
        content.sound = .default
        content.userInfo = [
            notificationWebmailURLKey: url.absoluteString,
            notificationAccountIDKey: account.id.uuidString
        ]

        let request = UNNotificationRequest(
            identifier: "mailbell.\(account.id.uuidString).\(header.uid)",
            content: content,
            trigger: nil
        )
        return await add(request)
    }

    private func add(_ request: UNNotificationRequest) async -> NotificationPostResult {
        do {
            try await notificationCenter.add(request)
            return .posted
        } catch {
            let message = error.localizedDescription
            Log.error("Failed to post notification: \(message)")
            return .failed(message)
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let urlString = response.notification.request.content.userInfo[notificationWebmailURLKey] as? String,
           let url = URL(string: urlString) {
            let accountID = (response.notification.request.content.userInfo[notificationAccountIDKey] as? String)
                .flatMap(UUID.init(uuidString:))
            Task { @MainActor in
                if let webmailOpenHandler {
                    await webmailOpenHandler(accountID, url)
                } else {
                    NSWorkspace.shared.open(url)
                }
                completionHandler()
            }
            return
        }
        completionHandler()
    }
}

private extension UNAuthorizationStatus {
    var mailbellDescription: String {
        switch self {
        case .notDetermined:
            return "Not requested"
        case .denied:
            return "Denied"
        case .authorized:
            return "Allowed"
        case .provisional:
            return "Allowed quietly"
        case .ephemeral:
            return "Allowed temporarily"
        @unknown default:
            return "Unknown"
        }
    }
}

private extension UNNotificationSetting {
    var mailbellDescription: String {
        switch self {
        case .notSupported:
            return "Not supported"
        case .disabled:
            return "Disabled"
        case .enabled:
            return "Enabled"
        @unknown default:
            return "Unknown"
        }
    }
}
