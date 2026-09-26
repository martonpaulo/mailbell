import Foundation
import MailbellKit

/// What the monitor and the supervisor post. `NotificationManager` is the one
/// production conformer, created once at launch and passed down by initializer,
/// so a test can record what a monitor posts instead of reaching the system
/// notification center.
@MainActor
protocol MailNotifying: AnyObject {
    func notify(_ header: MessageHeader, account: MailAccount) async -> NotificationPostResult
    @discardableResult
    func notifySignInNeeded(account: MailAccount) async -> NotificationPostResult
}
