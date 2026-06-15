import Foundation

extension AccountSupervisor {
    func markEmailAsRead(id: String) async {
        guard let item = emailStore.item(id: id) else { return }
        guard let identity = item.imapIdentity else {
            Log.error("Cannot mark email as read because the pending item has no IMAP UID.")
            return
        }
        guard let account = accounts.first(where: { $0.id == item.accountID }) else {
            Log.error("Cannot mark email as read because the account was not found.")
            return
        }

        do {
            let config = try configProvider()
            try await emailReadMarker(account, config, identity)
            emailStore.markRead(id: id)
            publish()
        } catch {
            handleMarkAsReadFailure(error, accountID: account.id)
        }
    }

    private func handleMarkAsReadFailure(_ error: Error, accountID: UUID) {
        Log.error("Failed to mark email as read: \(error.localizedDescription)")
        guard let oauthError = error as? OAuthClient.OAuthError else { return }

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
