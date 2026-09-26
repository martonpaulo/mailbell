import AppKit
import Foundation
import MailbellKit
import UserNotifications

// Nonisolated: read by the notification-center delegate callbacks off the main actor.
nonisolated let notificationWebmailURLKey = "webmailURL"
nonisolated let notificationAccountIDKey = "accountID"
nonisolated let notificationEmailIDKey = "emailID"
nonisolated let notificationEmailCategoryIdentifier = "mailbell.email"
nonisolated let notificationDismissActionIdentifier = "MAILBELL_DISMISS_EMAIL"

// Nonisolated: decided in the notification-center delegate callback off the main actor.
nonisolated enum EmailNotificationResponseAction: Equatable {
    case open(emailID: String?, accountID: UUID?, url: URL)
    case dismiss(emailID: String?)
}

struct NotificationAuthorizationState: Equatable {
    let isBundled: Bool
    let status: UNAuthorizationStatus
    let alertSetting: UNNotificationSetting
    let soundSetting: UNNotificationSetting

    static let unbundled = NotificationAuthorizationState(
        isBundled: false,
        status: .notDetermined,
        alertSetting: .notSupported,
        soundSetting: .notSupported
    )

    var canPostAlert: Bool {
        guard isBundled else { return false }
        guard status == .authorized || status == .provisional else { return false }
        return alertSetting == .enabled || alertSetting == .notSupported
    }

    var summary: String {
        guard isBundled else { return String(localized: "Unavailable outside app bundle") }
        return status.mailbellDescription
    }

    var detail: String {
        guard isBundled else {
            return String(localized: "Install and run Mailbell.app to use macOS notifications.")
        }
        if status == .denied {
            return String(localized: "Enable Mailbell in System Settings > Notifications.")
        }
        if status == .notDetermined {
            return String(localized: "Notification permission has not been requested yet.")
        }
        if !canPostAlert {
            return String(localized: "Notification alerts are disabled for Mailbell.")
        }
        return String(
            localized: "Alerts: \(alertSetting.mailbellDescription), Sound: \(soundSetting.mailbellDescription)")
    }

    var canRequestPermission: Bool {
        isBundled && status == .notDetermined
    }

    /// The person turned Mailbell's notifications off in System Settings.
    var isDenied: Bool {
        isBundled && status == .denied
    }

    /// Permission is granted, but macOS shows no banner or alert.
    var alertsOff: Bool {
        isGranted && alertSetting == .disabled
    }

    /// Permission is granted, but macOS plays no sound.
    var soundOff: Bool {
        isGranted && soundSetting == .disabled
    }

    private var isGranted: Bool {
        isBundled && (status == .authorized || status == .provisional)
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
        case .unavailable(let message):
            message
        case .notAuthorized(let state):
            state.detail
        case .failed(let message):
            message
        }
    }
}

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, MailNotifying {
    var emailOpenHandler: (@MainActor (String?, UUID?, URL) async -> Void)?
    var emailDismissHandler: (@MainActor (String?) async -> Void)?
    var webmailOpenHandler: (@MainActor (UUID?, URL) async -> Void)?

    private let settingsStore = AppSettingsStore()

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
        account: MailAccount,
        playNotificationSounds: Bool
    ) -> UNMutableNotificationContent {
        EmailNotificationContentBuilder.build(
            header: header,
            webmailURL: webmailURL(for: header, account: account),
            accountID: account.id,
            playNotificationSounds: playNotificationSounds,
            emailID: ReviewItemIdentity.id(accountID: account.id, header: header)
        )
    }

    nonisolated static let testNotificationTitle = String(localized: "Mailbell")
    nonisolated static let testNotificationBody = String(localized: "Test notification. New mail looks like this.")

    /// Says plainly that it is a test: a fake message from a made-up sender
    /// can be mistaken for real mail.
    nonisolated static func testNotificationContent(
        account: MailAccount?,
        playNotificationSounds: Bool
    ) -> UNMutableNotificationContent {
        let url =
            account.map { MailProviderRegistry.provider(for: $0.providerID).webmailURL(for: $0) }
            ?? GmailProvider().webmailURL
        let content = UNMutableNotificationContent()
        content.title = testNotificationTitle
        content.body = testNotificationBody
        content.sound = NotificationSoundPolicy.sound(playNotificationSounds: playNotificationSounds)
        var userInfo: [String: String] = [notificationWebmailURLKey: url.absoluteString]
        if let account {
            userInfo[notificationAccountIDKey] = account.id.uuidString
        }
        content.userInfo = userInfo
        return content
    }

    /// Created once at launch, before `applicationDidFinishLaunching` returns,
    /// so a notification response that launches the app finds its delegate.
    override init() {
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
            soundSetting: settings.soundSetting
        )
    }

    func requestAuthorization() async -> NotificationAuthorizationState {
        guard isBundled else {
            Log.notify.info(
                "Notifications unavailable (no app bundle); run the packaged .app for native notifications.")
            return .unbundled
        }
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            Log.notify.info("Notification authorization granted: \(granted, privacy: .public)")
        } catch {
            Log.notify.error("Notification authorization error: \(Log.detail(error), privacy: .private)")
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
            Self.notificationContent(
                for: header,
                account: account,
                playNotificationSounds: settingsStore.playNotificationSounds
            ),
            identifier: EmailNotificationContentBuilder.requestIdentifier(
                accountID: account.id,
                header: header
            )
        )
    }

    func notifyTest(account: MailAccount?) async -> NotificationPostResult {
        await post(
            Self.testNotificationContent(
                account: account,
                playNotificationSounds: settingsStore.playNotificationSounds
            ),
            identifier: "mailbell.test.\(UUID().uuidString)"
        )
    }

    @discardableResult
    func notifySignInNeeded(account: MailAccount) async -> NotificationPostResult {
        await post(
            SignInNotificationContentBuilder.build(
                account: account,
                playNotificationSounds: settingsStore.playNotificationSounds
            ),
            identifier: SignInNotificationContentBuilder.requestIdentifier(accountID: account.id)
        )
    }

    /// The single gate every notification passes through: bundled, authorized,
    /// then posted.
    private func post(_ content: UNNotificationContent, identifier: String) async -> NotificationPostResult {
        guard isBundled else {
            Log.notify.info(
                "Notifications unavailable outside app bundle; install Mailbell.app to post native notifications.")
            return .unavailable(String(localized: "Notifications unavailable outside app bundle."))
        }

        let state = await requestAuthorizationIfNeeded()
        guard state.canPostAlert else {
            Log.notify.error("Notification skipped: \(state.detail, privacy: .public)")
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
            Log.notify.error("Failed to post notification: \(Log.detail(error), privacy: .private)")
            return .failed(message)
        }
    }

    private func registerEmailCategory() {
        let dismissAction = UNNotificationAction(
            identifier: notificationDismissActionIdentifier,
            title: String(localized: "Dismiss"),
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

    nonisolated static func presentationOptions(
        for content: UNNotificationContent
    ) -> UNNotificationPresentationOptions {
        var options: UNNotificationPresentationOptions = [.banner]
        if content.sound != nil {
            options.insert(.sound)
        }
        return options
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.presentationOptions(for: notification.request.content))
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        guard
            let action = Self.responseAction(
                actionIdentifier: response.actionIdentifier,
                userInfo: response.notification.request.content.userInfo
            )
        else {
            completionHandler()
            return
        }

        Task { @MainActor in
            defer { completionHandler() }
            switch action {
            case .open(let emailID, let accountID, let url):
                if let emailOpenHandler {
                    await emailOpenHandler(emailID, accountID, url)
                } else if let webmailOpenHandler {
                    await webmailOpenHandler(accountID, url)
                } else {
                    NSWorkspace.shared.open(url)
                }
            case .dismiss(let emailID):
                if let emailDismissHandler {
                    await emailDismissHandler(emailID)
                }
            }
        }
    }
}

extension UNAuthorizationStatus {
    fileprivate var mailbellDescription: String {
        switch self {
        case .notDetermined:
            return String(localized: "Not requested")
        case .denied:
            return String(localized: "Denied")
        case .authorized:
            return String(localized: "Allowed")
        case .provisional:
            return String(localized: "Allowed quietly")
        case .ephemeral:
            return String(localized: "Allowed temporarily")
        @unknown default:
            return String(localized: "Unknown")
        }
    }
}

extension UNNotificationSetting {
    fileprivate var mailbellDescription: String {
        switch self {
        case .notSupported:
            return String(localized: "Not supported")
        case .disabled:
            return String(localized: "Disabled")
        case .enabled:
            return String(localized: "Enabled")
        @unknown default:
            return String(localized: "Unknown")
        }
    }
}
