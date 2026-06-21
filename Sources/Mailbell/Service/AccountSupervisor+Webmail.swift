import Foundation

extension AccountSupervisor {
    func updateWebmailPreference(accountID: UUID, preference: WebmailOpenPreference?) {
        guard var account = accounts.first(where: { $0.id == accountID }) else { return }
        guard account.webmailOpenPreference != preference else { return }
        account.webmailOpenPreference = preference
        accounts = accountStore.upsert(account)
        webmailOpenErrors[accountID] = nil
        publish()
    }

    func openGmail(accountID: UUID) async {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }
        let url = MailProviderRegistry.provider(for: account.providerID).webmailURL(for: account)
        await applyWebmailOpen(url: url, account: account, accountID: accountID)
    }

    func openWebmail(accountID: UUID?, url: URL) async {
        let account = accountID.flatMap { id in accounts.first(where: { $0.id == id }) }
        await applyWebmailOpen(url: url, account: account, accountID: account?.id ?? accountID)
    }

    func openEmail(id: String?, accountID: UUID?, url: URL) async {
        let storedItem = id.flatMap { emailStore.firstItemInGroup(containing: $0) }
        let resolvedAccountID = storedItem?.accountID ?? accountID
        let account = resolvedAccountID.flatMap { id in accounts.first(where: { $0.id == id }) }
        let outcome = await applyWebmailOpen(
            url: storedItem?.webmailURL ?? url,
            account: account,
            accountID: account?.id ?? resolvedAccountID
        )
        if outcome.didOpen, let id {
            emailStore.markOpened(id: id)
            publish()
        }
    }

    func openEmail(id: String) async {
        guard let item = emailStore.firstItemInGroup(containing: id) else { return }
        await openEmail(id: id, accountID: item.accountID, url: item.webmailURL)
    }

    func dismissEmail(id: String?) {
        guard let id else { return }
        emailStore.dismiss(id: id)
        publish()
    }

    @discardableResult
    private func applyWebmailOpen(url: URL, account: MailAccount?, accountID: UUID?) async -> WebmailOpenOutcome {
        let outcome = await webmailOpen(url, account)
        if let accountID {
            switch outcome {
            case .opened:
                webmailOpenErrors[accountID] = nil
            case let .openedWithFallback(message), let .failed(message):
                webmailOpenErrors[accountID] = message
            }
            publish()
        }
        return outcome
    }
}
