import Foundation

extension AccountSupervisor {
    func markEmailAsRead(id: String) async {
        guard let item = emailStore.item(id: id) else { return }
        let identities = emailStore.imapIdentitiesInGroup(containing: id)
        guard !identities.isEmpty else {
            Log.error("Cannot mark email as read because the pending item has no IMAP UID.")
            return
        }
        guard let account = accounts.first(where: { $0.id == item.accountID }) else {
            Log.error("Cannot mark email as read because the account was not found.")
            return
        }

        do {
            let config = try configProvider()
            try await emailReadMarker(account, config, identities)
            try emailStore.markRead(id: id)
            applyEmailStoreWarning(accountID: account.id)
            publish()
        } catch {
            applyMarkAsReadFailure(error, accountID: account.id)
            publish()
        }
    }

    /// Records a mark-as-read failure without publishing, so a bulk run can
    /// collect every account's outcome and notify observers exactly once.
    func applyMarkAsReadFailure(_ error: Error, accountID: UUID) {
        Log.error("Failed to mark email as read: \(error.localizedDescription)")
        if error is EmailStorePersistence.PersistenceError {
            applyEmailStorePersistenceFailure(error, accountID: accountID)
            return
        }
        guard let oauthError = error as? OAuthClient.OAuthError else {
            connectionErrors[accountID] = error.localizedDescription
            return
        }

        switch oauthError {
        case .refreshFailed, .noRefreshToken:
            statuses[accountID] = .reauthRequired
            connectionErrors[accountID] = oauthError.localizedDescription
        default:
            break
        }
    }
}
