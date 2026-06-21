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
            for identity in identities {
                try await emailReadMarker(account, config, identity)
            }
            try emailStore.markRead(id: id)
            applyEmailStoreWarning(accountID: account.id)
            publish()
        } catch {
            handleMarkAsReadFailure(error, accountID: account.id)
        }
    }

    private func handleMarkAsReadFailure(_ error: Error, accountID: UUID) {
        Log.error("Failed to mark email as read: \(error.localizedDescription)")
        if error is EmailStorePersistence.PersistenceError {
            handleEmailStorePersistenceFailure(error, accountID: accountID)
            return
        }
        guard let oauthError = error as? OAuthClient.OAuthError else {
            connectionErrors[accountID] = error.localizedDescription
            publish()
            return
        }

        switch oauthError {
        case .refreshFailed, .noRefreshToken:
            statuses[accountID] = .reauthRequired
            connectionErrors[accountID] = oauthError.localizedDescription
            publish()
        default:
            break
        }
    }
}
