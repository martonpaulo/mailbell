import Foundation
import MailbellKit
import UserNotifications

/// Expired sign-in is the one account failure Mailbell cannot recover from on
/// its own, and the menu bar alert glyph only helps a user who happens to look
/// at it. The title is the menu's problem row title (`MenuCopy.needsSignIn`),
/// so both surfaces name the state with one definition.
///
/// Nonisolated: a pure helper, like EmailNotificationContentBuilder.
nonisolated enum SignInNotificationContentBuilder {
    static func title(email: String) -> String {
        MenuCopy.needsSignIn(email)
    }

    static let body = String(
        localized: "Mailbell stopped watching this account. Choose Sign In Again in the Mailbell menu."
    )

    static func build(account: MailAccount, playNotificationSounds: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title(email: account.email)
        content.body = body
        content.sound = NotificationSoundPolicy.sound(playNotificationSounds: playNotificationSounds)
        return content
    }

    /// One request identifier per account, so a repeated alert replaces the
    /// previous one instead of stacking in Notification Center.
    static func requestIdentifier(accountID: UUID) -> String {
        "mailbell.signin.\(accountID.uuidString)"
    }
}
