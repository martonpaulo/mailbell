extension AccountSupervisor {
    enum ManualRefreshResult: Equatable {
        case requested(accountCount: Int)
        case noEnabledAccounts
        case signInRequired
        case unavailable

        var message: String {
            switch self {
            case .requested:
                "Sync requested. Mailbell will reconnect and update Gmail state."
            case .noEnabledAccounts:
                "Enable an account to sync Gmail."
            case .signInRequired:
                "Sign in again to sync Gmail."
            case .unavailable:
                "Sync unavailable. Check account setup."
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
            if statuses[account.id] == .reauthRequired {
                needsSignIn = true
                continue
            }

            guard let monitor = ensureMonitor(for: account) else {
                setupFailed = true
                continue
            }

            guard monitor.hasSession else {
                statuses[account.id] = .reauthRequired
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
