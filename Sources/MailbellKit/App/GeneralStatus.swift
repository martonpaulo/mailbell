import Foundation

/// The one-line status on the app card at the top of Settings › General.
///
/// A problem replaces the summary and follows the menu bar glyph's precedence
/// (docs/interface.md, "Menu bar glyph"): an account that needs the person
/// first, then a denied notification permission. Only enabled accounts count;
/// a paused account is a choice, not a problem.
public enum GeneralStatus {
    public static func text(
        accounts: [AccountRuntimeState],
        conversationsToReview: Int,
        notificationsDenied: Bool
    ) -> String {
        guard !accounts.isEmpty else {
            return String(localized: "No Gmail account. Add one in Accounts.")
        }
        let enabled = accounts.filter(\.account.isEnabled)

        let needingSignIn = enabled.filter { $0.status.needsSignIn }
        if let first = needingSignIn.first {
            return needingSignIn.count == 1
                ? String(localized: "\(first.account.email) needs sign-in.")
                : String(localized: "\(needingSignIn.count) accounts need sign-in.")
        }

        let failing = enabled.filter { $0.status == .error }
        if let first = failing.first {
            return failing.count == 1
                ? String(localized: "Can't connect to \(first.account.email).")
                : String(localized: "Can't connect to \(failing.count) accounts.")
        }

        if notificationsDenied {
            return String(localized: "Notifications are off in System Settings.")
        }

        guard !enabled.isEmpty else {
            return String(localized: "Paused. No account is being watched.")
        }
        return "\(watchingText(enabled.count)) \(reviewText(conversationsToReview))"
    }

    private static func watchingText(_ count: Int) -> String {
        count == 1
            ? String(localized: "Watching 1 account.")
            : String(localized: "Watching \(count) accounts.")
    }

    private static func reviewText(_ count: Int) -> String {
        switch count {
        case 0:
            String(localized: "Nothing to review.")
        case 1:
            String(localized: "1 conversation to review.")
        default:
            String(localized: "\(count) conversations to review.")
        }
    }
}
