@testable import Mailbell
import Foundation

/// Records what a monitor or supervisor posts, in place of NotificationManager.
@MainActor
final class RecordingNotifier: MailNotifying {
    private(set) var notifiedHeaders: [MessageHeader] = []
    private(set) var signInNeededAccounts: [MailAccount] = []
    var result: NotificationPostResult = .posted

    func notify(_ header: MessageHeader, account _: MailAccount) async -> NotificationPostResult {
        notifiedHeaders.append(header)
        return result
    }

    @discardableResult
    func notifySignInNeeded(account: MailAccount) async -> NotificationPostResult {
        signInNeededAccounts.append(account)
        return result
    }
}
