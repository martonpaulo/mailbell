import Foundation

/// What a monitor reports back: status, admissions, notification results, the
/// UIDs reconciliation should look past, and unread reconciliation. Kept apart
/// from the supervisor's own commands so each side reads on its own.
extension AccountSupervisor {
    nonisolated func monitor(
        _ accountID: UUID,
        uidsToSkipFor mailbox: MessageMailbox,
        mailboxName: String,
        uidValidity: Int
    ) async -> Set<Int> {
        await MainActor.run { [weak self] in
            guard let self,
                  let account = accounts.first(where: { $0.id == accountID })
            else {
                return []
            }
            return (try? emailStore.uidsToSkip(
                accountID: account.id,
                mailbox: mailbox,
                mailboxName: mailboxName,
                uidValidity: uidValidity
            )) ?? emailStore.pendingUIDs(
                accountID: account.id,
                mailbox: mailbox,
                uidValidity: uidValidity
            )
        }
    }

    nonisolated func monitor(
        _ accountID: UUID,
        didReconcileUnread snapshots: [MailboxUnreadSnapshot],
        fetchedHeaders: [MessageHeader]
    ) async {
        await MainActor.run { [weak self] in
            guard let self,
                  let account = accounts.first(where: { $0.id == accountID })
            else {
                return
            }
            let visibleSnapshots = includeSpam ? snapshots : snapshots.filter { $0.mailbox != .spam }
            let visibleHeaders = includeSpam ? fetchedHeaders : fetchedHeaders.filter { $0.mailbox != .spam }
            do {
                let didChange = try emailStore.reconcileUnread(
                    snapshots: visibleSnapshots,
                    fetchedHeaders: visibleHeaders,
                    account: account
                )
                let didWarn = applyEmailStoreWarning(accountID: account.id)
                guard didChange || didWarn else { return }
                publish()
            } catch {
                handleEmailStorePersistenceFailure(error, accountID: account.id)
            }
        }
    }

    nonisolated func monitor(
        _ accountID: UUID,
        shouldNotify headers: [MessageHeader]
    ) async -> Set<IMAPMessageIdentity> {
        await MainActor.run { [weak self] in
            guard let self,
                  let account = accounts.first(where: { $0.id == accountID })
            else {
                return []
            }
            let visibleHeaders = includeSpam ? headers : headers.filter { $0.mailbox != .spam }
            var admittedIdentities = Set<IMAPMessageIdentity>()
            var didChange = false

            for header in visibleHeaders {
                do {
                    guard try emailStore.admit(header: header, account: account) else { continue }
                    didChange = true
                    if let identity = header.imapIdentity {
                        admittedIdentities.insert(identity)
                    }
                } catch {
                    handleEmailStorePersistenceFailure(error, accountID: account.id)
                    return []
                }
            }

            let didWarn = applyEmailStoreWarning(accountID: account.id)
            if didChange || didWarn {
                publish()
            }
            return admittedIdentities
        }
    }

    nonisolated func monitor(_ accountID: UUID, didChangeStatus status: MonitorStatus, error: String?) {
        Task { @MainActor [weak self] in
            self?.statuses[accountID] = status
            if let error {
                self?.connectionErrors[accountID] = error
            } else if status.clearsLastError {
                self?.connectionErrors[accountID] = nil
            }
            self?.publish()
        }
    }

    nonisolated func monitor(_ accountID: UUID, didNotify _: MessageHeader, result: NotificationPostResult) {
        Task { @MainActor [weak self] in
            if let message = result.userMessage {
                self?.notificationErrors[accountID] = message
            } else {
                self?.notificationErrors[accountID] = nil
            }
            self?.publish()
        }
    }
}
