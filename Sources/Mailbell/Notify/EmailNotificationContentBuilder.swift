import Foundation
import UserNotifications

enum EmailNotificationContentBuilder {
    static func build(
        header: MessageHeader,
        webmailURL: URL,
        accountID: UUID?,
        emailID: String? = nil
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = EmailHeaderFormatter.senderTitle(from: header.from)
        content.body = EmailHeaderFormatter.title(for: header)
        content.sound = .default
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
