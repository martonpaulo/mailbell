import Foundation
import UserNotifications

enum EmailNotificationContentBuilder {
    static func build(
        header: MessageHeader,
        webmailURL: URL,
        accountID: UUID?,
        playNotificationSounds: Bool,
        emailID: String? = nil
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = EmailHeaderFormatter.senderTitle(from: header.from)
        let subject = EmailHeaderFormatter.title(for: header)
        if let bodyPreview = header.bodyPreview {
            content.subtitle = subject
            content.body = bodyPreview
        } else {
            content.body = subject
        }
        content.sound = NotificationSoundPolicy.sound(playNotificationSounds: playNotificationSounds)
        if emailID != nil {
            content.categoryIdentifier = notificationEmailCategoryIdentifier
        }

        var userInfo: [String: String] = [
            notificationWebmailURLKey: webmailURL.absoluteString
        ]
        if let accountID {
            userInfo[notificationAccountIDKey] = accountID.uuidString
        }
        if let emailID {
            userInfo[notificationEmailIDKey] = emailID
        }
        content.userInfo = userInfo
        return content
    }
}
