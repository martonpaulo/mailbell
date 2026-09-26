extension AccountSupervisor {
    enum ManualRefreshResult: Equatable {
        case requested(accountCount: Int)
        case noEnabledAccounts
        case signInRequired
        case unavailable

        var message: String {
            switch self {
            case .requested:
                String(localized: "Checking for new mail…")
            case .noEnabledAccounts:
                String(localized: "Resume watching an account to check for new mail.")
            case .signInRequired:
                String(localized: "Sign in again to check for new mail.")
            case .unavailable:
                String(localized: "Can't check for new mail. See Accounts in Settings.")
            }
        }
    }

    @discardableResult
    func refreshNow() -> ManualRefreshResult {
        let enabledAccounts = accounts.filter(\.isEnabled)
        guard !enabledAccounts.isEmpty else {
            publish()
            return .noEnabledAccounts
        }

        var requestedCount = 0
        var needsSignIn = false
        var setupFailed = false

        for account in enabledAccounts {
            if statuses[account.id] == .signInRequired {
                needsSignIn = true
                continue
            }

            guard let monitor = ensureMonitor(for: account) else {
                setupFailed = true
                continue
            }

            guard let hasSession = hasStoredSession(monitor, accountID: account.id) else {
                setupFailed = true
                continue
            }

            guard hasSession else {
                statuses[account.id] = .signInRequired
                needsSignIn = true
                continue
            }

            monitor.refreshNow()
            requestedCount += 1
        }

        publish()

        if requestedCount > 0 {
            return .requested(accountCount: requestedCount)
        }
        if needsSignIn {
            return .signInRequired
        }
        return setupFailed ? .unavailable : .noEnabledAccounts
    }
}
