import Foundation

/// The bounded reads: unread UID search, minimal headers, and a capped
/// non-mutating body preview. Every fetch here is deliberately small — this is
/// where Mailbell's data-minimisation contract is actually enforced.
extension IMAPClient {
    func fetchHeaders(uids: [Int]) async throws -> [MessageHeader] {
        var headers: [MessageHeader] = []
        for batch in IMAPUIDSequence.uidFetchBatches(for: uids) {
            let batchHeaders = try await fetchHeadersBatch(uids: batch)
            headers.append(contentsOf: batchHeaders)
        }
        return headers
    }

    func fetchHeadersBatch(uids: [Int]) async throws -> [MessageHeader] {
        let sequenceSet = IMAPUIDSequence.uidSequenceSet(for: uids)
        guard !sequenceSet.isEmpty else { return [] }

        let tag = nextTag()
        try await connection.send(
            "\(tag) UID FETCH \(sequenceSet) (UID INTERNALDATE X-GM-MSGID X-GM-THRID \(Self.headerFields))"
        )

        var headers: [MessageHeader] = []
        while true {
            let line = try await connection.readLine()
            if line.hasPrefix("* "), line.uppercased().contains("FETCH") {
                if let header = try await parseFetch(line) {
                    headers.append(header)
                }
                continue
            }
            if line.hasPrefix("\(tag) OK") {
                break
            }
            if line.hasPrefix("\(tag) NO") || line.hasPrefix("\(tag) BAD") {
                throw IMAPError.unexpected(line)
            }
        }
        guard !headers.isEmpty else { return [] }

        let previews = try await fetchBodyPreviewsBatch(uids: headers.map(\.uid))
        return headers.map { header in
            header.assigningBodyPreview(previews[header.uid])
        }
    }

    func fetchBodyPreviewsBatch(uids: [Int]) async throws -> [Int: String] {
        let sequenceSet = IMAPUIDSequence.uidSequenceSet(for: uids)
        guard !sequenceSet.isEmpty else { return [:] }

        let tag = nextTag()
        try await connection.send(
            "\(tag) UID FETCH \(sequenceSet) (UID BODY.PEEK[TEXT]<0.\(Self.bodyPreviewBytes)>)"
        )

        var previews: [Int: String] = [:]
        while true {
            let line = try await connection.readLine()
            if line.hasPrefix("* "), line.uppercased().contains("FETCH") {
                if let (uid, preview) = try await parseBodyPreviewFetch(line) {
                    previews[uid] = preview
                }
                continue
            }
            if line.hasPrefix("\(tag) OK") {
                break
            }
            if line.hasPrefix("\(tag) NO") || line.hasPrefix("\(tag) BAD") {
                throw IMAPError.unexpected(line)
            }
        }
        return previews
    }
}
