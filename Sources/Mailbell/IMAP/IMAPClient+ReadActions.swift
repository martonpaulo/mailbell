import Foundation

/// The one place Mailbell mutates a mailbox, and the generation guard that
/// keeps it from mutating the wrong one.
extension IMAPClient {
    func markAsRead(uid: Int, requiringUIDValidity: Int) async throws {
        guard uid > 0 else { throw IMAPError.invalidUID(uid) }
        try await markAsRead(uids: [uid], requiringUIDValidity: requiringUIDValidity)
    }

    /// One `UID STORE` per batch, so a bulk action costs a handful of commands
    /// rather than one round trip per message.
    func markAsRead(uids: [Int], requiringUIDValidity: Int) async throws {
        // Checked against the SELECT result rather than the caller's memory, so
        // a generation change between capture and action stops the STORE here.
        guard selectedUIDValidity == requiringUIDValidity else {
            throw IMAPError.staleMailboxGeneration(
                expected: requiringUIDValidity,
                actual: selectedUIDValidity ?? 0
            )
        }

        let validUIDs = uids.filter { $0 > 0 }
        guard !validUIDs.isEmpty else {
            throw IMAPError.invalidUID(uids.first ?? 0)
        }

        for batch in IMAPUIDSequence.uidFetchBatches(for: validUIDs) {
            let sequenceSet = IMAPUIDSequence.uidSequenceSet(for: batch)
            guard !sequenceSet.isEmpty else { continue }
            let tag = nextTag()
            try await connection.send("\(tag) UID STORE \(sequenceSet) +FLAGS.SILENT (\\Seen)")

            while true {
                let line = try await connection.readLine()
                if line.hasPrefix("\(tag) OK") {
                    break
                }
                if line.hasPrefix("\(tag) NO") || line.hasPrefix("\(tag) BAD") {
                    throw IMAPError.unexpected(line)
                }
            }
        }
    }
}
