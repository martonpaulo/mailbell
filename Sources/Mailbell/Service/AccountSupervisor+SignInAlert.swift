import Foundation

typealias SignInNeededNotifier = @MainActor (MailAccount) -> Void

extension AccountSupervisor {
    /// Every status change funnels through `statuses`, so this is the one place
    /// that sees an account fall out of monitoring. Only a fresh transition
    /// alerts: an account already waiting for sign-in must not notify again on
    /// unrelated updates, and a disabled account is not being watched at all.
    func notifyAccountsNeedingSignIn(previous: [UUID: MonitorStatus]) {
        for (accountID, status) in statuses
            where status == .reauthRequired && previous[accountID] != .reauthRequired {
            guard let account = accounts.first(where: { $0.id == accountID && $0.isEnabled }) else { continue }
            signInNeededNotifier(account)
        }
    }
}
