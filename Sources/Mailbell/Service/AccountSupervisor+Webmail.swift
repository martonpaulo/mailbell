import Foundation
import MailbellKit

extension AccountSupervisor {
    func updateWebmailPreference(accountID: UUID, preference: WebmailOpenPreference?) {
        guard var account = accounts.first(where: { $0.id == accountID }) else { return }
        guard account.webmailOpenPreference != preference else { return }
        account.webmailOpenPreference = preference
        do {
            accounts = try accountStore.upsert(account)
            accountStoreError = nil
            webmailOpenErrors[accountID] = nil
        } catch {
            accountStoreError = error.localizedDescription
            webmailOpenErrors[accountID] = error.localizedDescription
        }
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

    func open(itemID id: String?, accountID: UUID?, url: URL) async {
        let storedItem = id.flatMap { reviewQueue.firstItemInGroup(containing: $0) }
        let resolvedAccountID = storedItem?.accountID ?? accountID
        let account = resolvedAccountID.flatMap { id in accounts.first(where: { $0.id == id }) }
        let outcome = await applyWebmailOpen(
            url: storedItem?.webmailURL ?? url,
            account: account,
            accountID: account?.id ?? resolvedAccountID
        )
        if outcome.didOpen, let id {
            do {
                try reviewQueue.markOpened(id: id)
                applyReviewQueueWarning(accountID: resolvedAccountID)
                publish()
            } catch {
                handleHandledHistoryFailure(error, accountID: resolvedAccountID)
            }
        }
    }

    func open(itemID id: String) async {
        guard let item = reviewQueue.firstItemInGroup(containing: id) else { return }
        await open(itemID: id, accountID: item.accountID, url: item.webmailURL)
    }

    func dismiss(itemID id: String?) {
        guard let id else { return }
        let accountID =
            reviewQueue.item(id: id)?.accountID
            ?? reviewQueue.firstItemInGroup(containing: id)?.accountID
        do {
            try reviewQueue.dismiss(id: id)
            applyReviewQueueWarning(accountID: accountID)
            publish()
        } catch {
            handleHandledHistoryFailure(error, accountID: accountID)
        }
    }

    @discardableResult
    private func applyWebmailOpen(url: URL, account: MailAccount?, accountID: UUID?) async -> WebmailOpenOutcome {
        let outcome = await webmailOpen(url, account)
        if let accountID {
            switch outcome {
            case .opened:
                webmailOpenErrors[accountID] = nil
            case .openedWithFallback(let message), .failed(let message):
                webmailOpenErrors[accountID] = message
            }
            publish()
        }
        return outcome
    }
}
