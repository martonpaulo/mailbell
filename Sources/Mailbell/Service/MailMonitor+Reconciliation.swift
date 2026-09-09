import Foundation

/// The two halves of a reconciliation pass: admitting and notifying about fresh
/// mail above the checkpoint, then syncing unread state so mail read in Gmail
/// leaves the queue and bounded unknown unread mail can enter it.
extension MailMonitor {
    func fetchAndNotify(client: IMAPClient, mailboxes: [MonitoredMailbox]) async throws {
        for mailbox in mailboxes {
            let generation = try await client.selectMailbox(mailbox.name).uidValidity
            let checkpointUID = lastSeenUID(for: mailbox.role)
            let from = max(checkpointUID + 1, 1)
            let uids = try await client.searchUnreadUIDs(fromUID: from)
            let plan = Self.notificationPlan(uids: uids, lastSeenUID: checkpointUID)

            let uidsToNotify = Set(plan.uidsToNotify)
            var notificationUIDsToFetch = uidsToNotify
            for admissionBatch in plan.admissionBatches {
                let headers = try await client.fetchHeaders(uids: admissionBatch)
                    .map { $0.assigningMailbox(mailbox.role, name: mailbox.name, uidValidity: generation) }
                    .sorted { $0.uid < $1.uid }

                let admittedIdentities = await delegate?.monitor(account.id, shouldNotify: headers)
                    ?? Set(headers.compactMap(\.imapIdentity))
                await notify(headers: headers, admittedIdentities: admittedIdentities, uidsToNotify: uidsToNotify)
                notificationUIDsToFetch.subtract(admissionBatch)

                if let admittedThroughUID = admissionBatch.last {
                    setLastSeenUID(Swift.max(lastSeenUID(for: mailbox.role), admittedThroughUID), for: mailbox.role)
                }

                if !notificationUIDsToFetch.isEmpty {
                    let notificationHeaders = try await client.fetchHeaders(
                        uids: Array(notificationUIDsToFetch).sorted()
                    )
                        .map { $0.assigningMailbox(mailbox.role, name: mailbox.name, uidValidity: generation) }
                        .sorted { $0.uid < $1.uid }
                    notificationUIDsToFetch.removeAll()
                    let admittedNotificationIdentities = await delegate?.monitor(
                        account.id,
                        shouldNotify: notificationHeaders
                    ) ?? Set(notificationHeaders.compactMap(\.imapIdentity))
                    await notify(
                        headers: notificationHeaders,
                        admittedIdentities: admittedNotificationIdentities,
                        uidsToNotify: uidsToNotify
                    )
                }
                await Task.yield()
            }
        }
    }

    func notify(
        headers: [MessageHeader],
        admittedIdentities: Set<IMAPMessageIdentity>,
        uidsToNotify: Set<Int>
    ) async {
        for header in headers {
            guard let identity = header.imapIdentity,
                  admittedIdentities.contains(identity),
                  uidsToNotify.contains(header.uid)
            else {
                continue
            }
            let result = await NotificationManager.shared.notify(header, account: account)
            delegate?.monitor(account.id, didNotify: header, result: result)
        }
    }

    func syncUnreadStore(client: IMAPClient, mailboxes: [MonitoredMailbox]) async throws {
        var snapshots: [MailboxUnreadSnapshot] = []
        var fetchedHeaders: [MessageHeader] = []
        for mailbox in mailboxes {
            let generation = try await client.selectMailbox(mailbox.name).uidValidity
            let searchedUIDs = try await client.searchUnreadUIDs()
            let unreadUIDs = Set(searchedUIDs.filter { $0 > 0 })
            snapshots.append(
                MailboxUnreadSnapshot(
                    mailbox: mailbox.role,
                    mailboxName: mailbox.name,
                    uidValidity: generation,
                    unreadUIDs: unreadUIDs
                )
            )

            let uidsToSkip = await delegate?.monitor(
                account.id,
                uidsToSkipFor: mailbox.role,
                mailboxName: mailbox.name,
                uidValidity: generation
            ) ?? []
            let unknownUIDs = Array(unreadUIDs.subtracting(uidsToSkip)).sorted()
            let uidsToFetch = Array(unknownUIDs.suffix(Self.maximumReconciliationHeadersPerMailbox))
            let mailboxHeaders = try await client.fetchHeaders(uids: uidsToFetch)
                .map { $0.assigningMailbox(mailbox.role, name: mailbox.name, uidValidity: generation) }
            fetchedHeaders.append(contentsOf: mailboxHeaders)
        }
        await delegate?.monitor(account.id, didReconcileUnread: snapshots, fetchedHeaders: fetchedHeaders)
    }
}
