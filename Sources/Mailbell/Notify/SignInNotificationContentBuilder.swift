import Foundation
import UserNotifications

/// Expired sign-in is the one account failure Mailbell cannot recover from on
/// its own, and the menu bar alert glyph only helps a user who happens to look
/// at it. The wording lives here so the notification and any future surface
/// share one definition.
enum SignInNotificationContentBuilder {
    static let title = "Sign in needed"

    static func body(email: String) -> String {
        "Mailbell stopped watching \(email). Open Mailbell settings to sign in again."
    }

    static func build(account: MailAccount) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body(email: account.email)
        content.sound = .default
        return content
    }

    /// One request identifier per account, so a repeated alert replaces the
    /// previous one instead of stacking in Notification Center.
    static func requestIdentifier(accountID: UUID) -> String {
        "mailbell.signin.\(accountID.uuidString)"
    }
}
