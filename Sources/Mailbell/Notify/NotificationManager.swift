import AppKit
import Foundation
import UserNotifications

let notificationWebmailURLKey = "webmailURL"
let notificationAccountIDKey = "accountID"
let notificationEmailIDKey = "emailID"
let notificationEmailCategoryIdentifier = "mailbell.email"
let notificationDismissActionIdentifier = "MAILBELL_DISMISS_EMAIL"

enum EmailNotificationResponseAction: Equatable {
    case open(emailID: String?, accountID: UUID?, url: URL)
    case dismiss(emailID: String?)
}

struct NotificationAuthorizationState: Equatable {
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

    var canRequestPermission: Bool {
        isBundled && status == .notDetermined
    }

    var shouldOpenSystemSettings: Bool {
        guard isBundled else { return false }
        guard status != .notDetermined else { return false }
        return !canPostAlert
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
            nil
        case let .unavailable(message):
            message
        case let .notAuthorized(state):
            state.detail
        case let .failed(message):
            message
        }
    }
}

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    var emailOpenHandler: (@MainActor (String?, UUID?, URL) async -> Void)?
    var emailDismissHandler: (@MainActor (String?) async -> Void)?
    var webmailOpenHandler: (@MainActor (UUID?, URL) async -> Void)?

    /// Resolved on demand: `UNUserNotificationCenter.current()` raises outside a
    /// real app bundle, so every use sits behind `isBundled`.
    private var notificationCenter: UNUserNotificationCenter {
        UNUserNotificationCenter.current()
    }

    private var isBundled: Bool {
        AppIdentity.isPackagedApp
    }

    nonisolated static func webmailURL(for header: MessageHeader, account: MailAccount) -> URL {
        MailProviderRegistry.provider(for: account.providerID).webmailURL(for: header, account: account)
    }

    nonisolated static func notificationContent(
        for header: MessageHeader,
        account: MailAccount
    ) -> UNMutableNotificationContent {
        EmailNotificationContentBuilder.build(
            header: header,
            webmailURL: webmailURL(for: header, account: account),
            accountID: account.id,
            emailID: EmailStoreIdentity.id(accountID: account.id, header: header)
        )
    }

    nonisolated static func testNotificationContent(account: MailAccount?) -> UNMutableNotificationContent {
        let header = MessageHeader(
            uid: 0,
            from: "Taylor Reed <taylor@example.com>",
            subject: "Contract review today",
            date: "",
            gmThreadId: nil,
            bodyPreview: "Please review the updated contract notes before the afternoon sync."
        )
        let url = account.map { webmailURL(for: header, account: $0) } ?? GmailProvider().webmailURL
        return EmailNotificationContentBuilder.build(
            header: header,
            webmailURL: url,
            accountID: account?.id
        )
    }

    override private init() {
        super.init()
        if isBundled {
            notificationCenter.delegate = self
            registerEmailCategory()
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
        await post(
            Self.notificationContent(for: header, account: account),
            identifier: "mailbell.\(account.id.uuidString).\(header.uid)"
        )
    }

    func notifyTest(account: MailAccount?) async -> NotificationPostResult {
        await post(
            Self.testNotificationContent(account: account),
            identifier: "mailbell.test.\(UUID().uuidString)"
        )
    }

    @discardableResult
    func notifySignInNeeded(account: MailAccount) async -> NotificationPostResult {
        await post(
            SignInNotificationContentBuilder.build(account: account),
            identifier: SignInNotificationContentBuilder.requestIdentifier(accountID: account.id)
        )
    }

    /// The single gate every notification passes through: bundled, authorized,
    /// then posted.
    private func post(_ content: UNNotificationContent, identifier: String) async -> NotificationPostResult {
        guard isBundled else {
            Log.info("Notifications unavailable outside app bundle; install Mailbell.app to post native notifications.")
            return .unavailable("Notifications unavailable outside app bundle.")
        }

        let state = await requestAuthorizationIfNeeded()
        guard state.canPostAlert else {
            Log.error("Notification skipped: \(state.detail)")
            return .notAuthorized(state)
        }

        return await add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
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

    private func registerEmailCategory() {
        let dismissAction = UNNotificationAction(
            identifier: notificationDismissActionIdentifier,
            title: "Dismiss",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: notificationEmailCategoryIdentifier,
            actions: [dismissAction],
            intentIdentifiers: [],
            options: []
        )
        notificationCenter.setNotificationCategories([category])
    }

    nonisolated static func responseAction(
        actionIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> EmailNotificationResponseAction? {
        let emailID = userInfo[notificationEmailIDKey] as? String

        if actionIdentifier == notificationDismissActionIdentifier {
            return .dismiss(emailID: emailID)
        }

        guard actionIdentifier == UNNotificationDefaultActionIdentifier,
              let urlString = userInfo[notificationWebmailURLKey] as? String,
              let url = URL(string: urlString)
        else {
            return nil
        }

        let accountID = (userInfo[notificationAccountIDKey] as? String)
            .flatMap(UUID.init(uuidString:))
        return .open(emailID: emailID, accountID: accountID, url: url)
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
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        guard let action = Self.responseAction(
            actionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo
        ) else {
            completionHandler()
            return
        }

        Task { @MainActor in
            defer { completionHandler() }
            switch action {
            case let .open(emailID, accountID, url):
                if let emailOpenHandler {
                    await emailOpenHandler(emailID, accountID, url)
                } else if let webmailOpenHandler {
                    await webmailOpenHandler(accountID, url)
                } else {
                    NSWorkspace.shared.open(url)
                }
            case let .dismiss(emailID):
                if let emailDismissHandler {
                    await emailDismissHandler(emailID)
                }
            }
        }
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
