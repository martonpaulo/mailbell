import Foundation

/// Adding, re-authorizing, enabling, reconnecting and removing an account.
/// These are the commands the interface issues; the supervisor itself holds the
/// state they act on.
extension AccountSupervisor {
    func addGmailAccount() async throws {
        let config = try configProvider()
        let result = try await signIn(config: config)
        let account = signedInAccount(email: result.email, providerID: .gmail)
        try saveSession(result.tokens, account: account)
        accounts = try accountStore.upsert(account)
        accountStoreError = nil
        statuses[account.id] = .signedOut
        connectionErrors[account.id] = nil
        start(account)
        publish()
    }

    func reauthenticate(accountID: UUID) async throws {
        guard accounts.contains(where: { $0.id == accountID }) else {
            throw SupervisorError.missingAccount
        }

        let config = try configProvider()
        let result = try await signIn(config: config)
        guard let account = accounts.first(where: { $0.id == accountID }) else {
            throw SupervisorError.missingAccount
        }
        guard account.email.caseInsensitiveCompare(result.email) == .orderedSame else {
            throw SupervisorError.accountMismatch(expected: account.email, actual: result.email)
        }
        try saveSession(result.tokens, account: account)
        accounts = try accountStore.upsert(account)
        accountStoreError = nil
        statuses[account.id] = .signedOut
        connectionErrors[account.id] = nil
        start(account)
        publish()
    }

    func setEnabled(_ isEnabled: Bool, accountID: UUID) {
        guard var account = accounts.first(where: { $0.id == accountID }) else { return }
        account.isEnabled = isEnabled
        do {
            accounts = try accountStore.upsert(account)
            accountStoreError = nil
            connectionErrors[accountID] = nil
        } catch {
            accountStoreError = error.localizedDescription
            connectionErrors[accountID] = error.localizedDescription
            publish()
            return
        }

        if isEnabled {
            start(account)
        } else {
            monitors[accountID]?.stop(clearSession: false)
            statuses[accountID] = .signedOut
            connectionErrors[accountID] = nil
            notificationErrors[accountID] = nil
            webmailOpenErrors[accountID] = nil
        }
        publish()
    }

    func setIncludeSpam(_ includeSpam: Bool) {
        guard self.includeSpam != includeSpam else { return }
        self.includeSpam = includeSpam
        for monitor in monitors.values {
            monitor.setIncludeSpam(includeSpam)
        }
        if !includeSpam, emailStore.removeSpamItems() {
            publish()
            return
        }
        publish()
    }

    func reconnect(accountID: UUID) {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        guard let monitor = ensureMonitor(for: account) else {
            publish()
            return
        }
        guard let hasSession = hasStoredSession(monitor, accountID: accountID) else {
            publish()
            return
        }
        if hasSession {
            monitor.forceReconnect()
            monitor.start()
        } else {
            statuses[accountID] = .reauthRequired
        }
        publish()
    }

    func remove(accountID: UUID) {
        guard accounts.contains(where: { $0.id == accountID }) else { return }
        let remainingAccounts: [MailAccount]
        do {
            try emailStore.removeAccountRecords(accountID: accountID)
            remainingAccounts = try accountStore.remove(accountID: accountID)
            accountStoreError = nil
        } catch {
            accountStoreError = error.localizedDescription
            connectionErrors[accountID] = error.localizedDescription
            publish()
            return
        }

        monitors[accountID]?.stop(clearSession: true)
        monitors[accountID] = nil
        statuses[accountID] = nil
        connectionErrors[accountID] = nil
        notificationErrors[accountID] = nil
        webmailOpenErrors[accountID] = nil
        CheckpointStore(accountID: accountID).reset()
        CheckpointStore(accountID: accountID, mailbox: "SPAM").reset()
        TokenStore(accountID: accountID).clear()
        emailStore.removeAccountItems(accountID: accountID)
        accounts = remainingAccounts
        applyEmailStoreWarning(accountID: nil)
        publish()
    }

    func forceReconnectAll() {
        let enabledAccountIDs = accounts.filter(\.isEnabled).map(\.id)
        reconnectAllTask?.cancel()
        reconnectAllTask = Task { @MainActor [weak self, enabledAccountIDs] in
            for (index, accountID) in enabledAccountIDs.enumerated() {
                let jitter = UInt64.random(in: 0 ... 300_000_000)
                let stagger = UInt64(index) * 300_000_000
                do {
                    try await Task.sleep(nanoseconds: jitter + stagger)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.reconnectIfSessionExists(accountID: accountID)
            }
        }
        publish()
    }
}
