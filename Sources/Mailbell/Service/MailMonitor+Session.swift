import Foundation

/// Turning a burst of fresh UIDs into bounded admission batches and a capped
/// notification set, plus the session work that surrounds it: tokens, mailbox
/// discovery, and the checkpoint the next reconnect resumes from.
extension MailMonitor {
    static func notificationPlan(
        uids: [Int],
        lastSeenUID: Int,
        notificationLimit: Int = maximumNotificationsPerFetch,
        admissionBatchSize: Int = maximumFreshHeadersPerAdmissionBatch
    ) -> NotificationPlan {
        let fresh = Array(Set(uids.filter { $0 > lastSeenUID })).sorted()
        guard !fresh.isEmpty else {
            return NotificationPlan(admissionBatches: [], uidsToNotify: [], lastSeenUID: lastSeenUID)
        }
        let admissionBatches = Self.admissionBatches(uids: fresh, batchSize: admissionBatchSize)
        let checkpointUID = admissionBatches.last?.last ?? lastSeenUID
        let uidsToNotify = notificationLimit > 0 ? Array(fresh.suffix(notificationLimit)) : []
        return NotificationPlan(
            admissionBatches: admissionBatches,
            uidsToNotify: uidsToNotify,
            lastSeenUID: checkpointUID
        )
    }

    private static func admissionBatches(uids: [Int], batchSize: Int) -> [[Int]] {
        guard batchSize > 0 else { return [] }
        var batches: [[Int]] = []
        var start = uids.startIndex
        while start < uids.endIndex {
            let end = uids.index(start, offsetBy: batchSize, limitedBy: uids.endIndex) ?? uids.endIndex
            batches.append(Array(uids[start ..< end]))
            start = end
        }
        return batches
    }

    static func monitoredMailboxes(includeSpam: Bool, spamMailboxName: String?) -> [MonitoredMailbox] {
        var mailboxes = [MonitoredMailbox(role: .inbox, name: "INBOX")]
        guard includeSpam,
              let spamMailboxName = spamMailboxName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !spamMailboxName.isEmpty
        else {
            return mailboxes
        }
        mailboxes.append(MonitoredMailbox(role: .spam, name: spamMailboxName))
        return mailboxes
    }

    static func userVisibleReconnectError(for error: Error) -> String? {
        if let connectionError = error as? IMAPConnection.ConnectionError,
           case .closed = connectionError {
            return nil
        }
        return error.localizedDescription
    }

    // MARK: - Tokens

    func validAccessToken() async throws -> String {
        if let accessTokenSource {
            return try await accessTokenSource()
        }
        return try await tokenProvider.validAccessToken()
    }

    private func refreshAccessToken() async throws -> String {
        try await tokenProvider.refreshAccessToken()
    }

    func authenticate(client: IMAPClient, email: String, accessToken: String) async throws {
        do {
            try await client.authenticate(email: email, accessToken: accessToken)
        } catch let error as IMAPClient.IMAPError {
            guard case .authFailed = error else { throw error }
            let refreshedAccessToken = try await refreshAccessToken()
            try await client.authenticate(email: email, accessToken: refreshedAccessToken)
        }
    }

    // MARK: - Checkpoint / gap fill
}
