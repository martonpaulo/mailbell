import Foundation

protocol IMAPClientTransport: Sendable {
    func connect() async throws
    func cancel()
    func send(_ line: String) async throws
    func sendRaw(_ text: String) async throws
    func readLine() async throws -> String
    func readBytes(_ count: Int) async throws -> Data
}

/// High-level Gmail IMAP client: XOAUTH2 auth, mailbox select, IDLE, and header
/// fetch. Built on top of the line-oriented `IMAPConnection`.
final class IMAPClient {
    enum IMAPError: Error, LocalizedError {
        case authFailed(String)
        case selectFailed(String)
        case unexpected(String)
        case invalidUID(Int)

        var errorDescription: String? {
            switch self {
            case let .authFailed(detail): "IMAP authentication failed: \(detail)"
            case let .selectFailed(detail): "IMAP SELECT failed: \(detail)"
            case let .unexpected(detail): "Unexpected IMAP response: \(detail)"
            case let .invalidUID(uid): "Invalid IMAP UID: \(uid)"
            }
        }
    }

    enum IdleEvent: Equatable {
        case newMessages(exists: Int)
        case mailboxChanged
        case timedOut
    }

    enum SpecialUseMailbox {
        case junk

        var flag: String {
            switch self {
            case .junk:
                "\\Junk"
            }
        }
    }

    /// Ensures `DONE` is sent at most once per IDLE, even though both the timeout
    /// task and the read loop may race to end the IDLE.
    private actor DoneGate {
        private var claimed = false
        func claim() -> Bool {
            if claimed {
                return false
            }
            claimed = true
            return true
        }
    }

    private let connection: any IMAPClientTransport
    private var tagCounter = 0
    private static let headerFields = "BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)]"
    private static let bodyPreviewBytes = 8192
    private static let maximumUIDsPerFetchCommand = 100
    private static let maximumUIDFetchSequenceSetLength = 1500

    init(host: String = "imap.gmail.com", port: UInt16 = 993) {
        connection = IMAPConnection(host: host, port: port)
    }

    init(connection: any IMAPClientTransport) {
        self.connection = connection
    }

    private func nextTag() -> String {
        tagCounter += 1
        return "A\(String(format: "%04d", tagCounter))"
    }

    func connect() async throws {
        try await connection.connect()
        // Consume the server greeting (`* OK ...`).
        _ = try await connection.readLine()
    }

    func disconnect() {
        connection.cancel()
    }

    // MARK: - Authentication

    func authenticate(email: String, accessToken: String) async throws {
        let authString = "user=\(email)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
        let encoded = Data(authString.utf8).base64EncodedString()
        let tag = nextTag()
        try await connection.send("\(tag) AUTHENTICATE XOAUTH2 \(encoded)")

        while true {
            let line = try await connection.readLine()
            if line.hasPrefix("+ ") {
                // Server returned a base64 error challenge; send an empty line to
                // let it surface the tagged NO response.
                try await connection.send("")
                continue
            }
            if line.hasPrefix("\(tag) OK") {
                return
            }
            if line.hasPrefix("\(tag) NO") || line.hasPrefix("\(tag) BAD") {
                throw IMAPError.authFailed(line)
            }
        }
    }

    // MARK: - Select

    @discardableResult
    func selectInbox() async throws -> MailboxState {
        try await selectMailbox("INBOX")
    }

    @discardableResult
    func selectMailbox(_ mailboxName: String) async throws -> MailboxState {
        let tag = nextTag()
        try await connection.send("\(tag) SELECT \(Self.quotedString(mailboxName))")
        var state = MailboxState(uidValidity: 0, uidNext: 0, exists: 0)

        while true {
            let line = try await connection.readLine()
            if let exists = IMAPParser.parseUntagged(line, suffix: "EXISTS") {
                state.exists = exists
            }
            if let uidValidity = IMAPParser.parseBracket(line, key: "UIDVALIDITY") {
                state.uidValidity = uidValidity
            }
            if let uidNext = IMAPParser.parseBracket(line, key: "UIDNEXT") {
                state.uidNext = uidNext
            }
            if line.hasPrefix("\(tag) OK") {
                return state
            }
            if line.hasPrefix("\(tag) NO") || line.hasPrefix("\(tag) BAD") {
                throw IMAPError.selectFailed(line)
            }
        }
    }

    func mailboxName(for specialUse: SpecialUseMailbox) async throws -> String? {
        let tag = nextTag()
        try await connection.send("\(tag) LIST \"\" \"*\"")

        var mailboxName: String?
        while true {
            let line = try await connection.readLine()
            if mailboxName == nil {
                mailboxName = IMAPParser.parseSpecialUseMailbox(line, flag: specialUse.flag)
            }
            if line.hasPrefix("\(tag) OK") {
                return mailboxName
            }
            if line.hasPrefix("\(tag) NO") || line.hasPrefix("\(tag) BAD") {
                throw IMAPError.unexpected(line)
            }
        }
    }

    // MARK: - IDLE

    /// Enters IDLE and returns when new messages arrive or `timeout` elapses
    /// (re-arm window). The caller loops on this.
    func idle(timeout: TimeInterval) async throws -> IdleEvent {
        let tag = nextTag()
        try await connection.send("\(tag) IDLE")
        // Expect the `+ idling` continuation.
        let cont = try await connection.readLine()
        guard cont.hasPrefix("+") else {
            throw IMAPError.unexpected(cont)
        }

        let gate = DoneGate()
        let connection = connection

        let timeoutTask = Task { [connection, gate] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if await gate.claim() {
                try? await connection.sendRaw("DONE\r\n")
            }
        }
        defer { timeoutTask.cancel() }

        var event: IdleEvent?
        while true {
            let line = try await connection.readLine()
            if let exists = IMAPParser.parseUntagged(line, suffix: "EXISTS") {
                event = .newMessages(exists: exists)
                if await gate.claim() {
                    try? await connection.sendRaw("DONE\r\n")
                }
            } else if Self.isFlagFetch(line) {
                event = .mailboxChanged
                if await gate.claim() {
                    try? await connection.sendRaw("DONE\r\n")
                }
            }
            if line.hasPrefix("\(tag) OK") {
                return event ?? .timedOut
            }
            if line.hasPrefix("\(tag) NO") || line.hasPrefix("\(tag) BAD") {
                throw IMAPError.unexpected(line)
            }
        }
    }

    // MARK: - Search and fetch headers

    /// Returns message UIDs in `[fromUID, *]` without fetching header payloads.
    func searchUIDs(fromUID: Int) async throws -> [Int] {
        try await searchUIDs(criteria: "UID \(max(fromUID, 1)):*")
    }

    /// Returns unread message UIDs in the selected mailbox.
    func searchUnreadUIDs() async throws -> [Int] {
        try await searchUIDs(criteria: "UNSEEN")
    }

    /// Returns unread message UIDs in `[fromUID, *]` without fetching header payloads.
    func searchUnreadUIDs(fromUID: Int) async throws -> [Int] {
        try await searchUIDs(criteria: "UID \(max(fromUID, 1)):* UNSEEN")
    }

    private func searchUIDs(criteria: String) async throws -> [Int] {
        let tag = nextTag()
        try await connection.send("\(tag) UID SEARCH \(criteria)")

        var uids: [Int] = []
        while true {
            let line = try await connection.readLine()
            if let searchedUIDs = IMAPParser.parseSearchUIDs(line) {
                uids.append(contentsOf: searchedUIDs)
                continue
            }
            if line.hasPrefix("\(tag) OK") {
                return uids
            }
            if line.hasPrefix("\(tag) NO") || line.hasPrefix("\(tag) BAD") {
                throw IMAPError.unexpected(line)
            }
        }
    }

    /// Fetches headers for a specific set of UIDs.
    func fetchHeaders(uids: [Int]) async throws -> [MessageHeader] {
        var headers: [MessageHeader] = []
        for batch in Self.uidFetchBatches(for: uids) {
            let batchHeaders = try await fetchHeadersBatch(uids: batch)
            headers.append(contentsOf: batchHeaders)
        }
        return headers
    }

    private func fetchHeadersBatch(uids: [Int]) async throws -> [MessageHeader] {
        let sequenceSet = Self.uidSequenceSet(for: uids)
        guard !sequenceSet.isEmpty else { return [] }

        let tag = nextTag()
        try await connection.send(
            "\(tag) UID FETCH \(sequenceSet) (UID X-GM-MSGID X-GM-THRID \(Self.headerFields))"
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

    private func fetchBodyPreviewsBatch(uids: [Int]) async throws -> [Int: String] {
        let sequenceSet = Self.uidSequenceSet(for: uids)
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

    func markAsRead(uid: Int) async throws {
        guard uid > 0 else { throw IMAPError.invalidUID(uid) }
        try await markAsRead(uids: [uid])
    }

    /// Marks every UID in the selected mailbox as read with one `UID STORE` per
    /// batch, so a bulk action costs a handful of commands instead of one round
    /// trip per message.
    func markAsRead(uids: [Int]) async throws {
        let validUIDs = uids.filter { $0 > 0 }
        guard !validUIDs.isEmpty else {
            throw IMAPError.invalidUID(uids.first ?? 0)
        }

        for batch in Self.uidFetchBatches(for: validUIDs) {
            let sequenceSet = Self.uidSequenceSet(for: batch)
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

    static func uidSequenceSet(for uids: [Int]) -> String {
        let sortedUIDs = Array(Set(uids.filter { $0 > 0 })).sorted()
        guard let first = sortedUIDs.first else { return "" }

        var ranges: [String] = []
        var start = first
        var previous = first

        for uid in sortedUIDs.dropFirst() {
            if uid == previous + 1 {
                previous = uid
                continue
            }
            ranges.append(sequenceRange(start: start, end: previous))
            start = uid
            previous = uid
        }

        ranges.append(sequenceRange(start: start, end: previous))
        return ranges.joined(separator: ",")
    }

    private static func uidFetchBatches(for uids: [Int]) -> [[Int]] {
        let sortedUIDs = Array(Set(uids.filter { $0 > 0 })).sorted()
        var batches: [[Int]] = []
        var current: [Int] = []

        for uid in sortedUIDs {
            let candidate = current + [uid]
            if !current.isEmpty,
               candidate.count > maximumUIDsPerFetchCommand
               || uidSequenceSet(for: candidate).count > maximumUIDFetchSequenceSetLength {
                batches.append(current)
                current = [uid]
            } else {
                current = candidate
            }
        }

        if !current.isEmpty {
            batches.append(current)
        }
        return batches
    }

    private static func sequenceRange(start: Int, end: Int) -> String {
        start == end ? "\(start)" : "\(start):\(end)"
    }

    private static func quotedString(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func isFlagFetch(_ line: String) -> Bool {
        let uppercased = line.uppercased()
        return line.hasPrefix("* ") && uppercased.contains("FETCH") && uppercased.contains("FLAGS")
    }

    private func parseFetch(_ firstLine: String) async throws -> MessageHeader? {
        guard let literalSize = IMAPParser.parseLiteralSize(firstLine) else {
            return nil
        }
        let block = try await connection.readBytes(literalSize)
        _ = try await connection.readLine()
        return IMAPParser.parseFetch(firstLine: firstLine, headerBlock: block)
    }

    private func parseBodyPreviewFetch(_ firstLine: String) async throws -> (uid: Int, preview: String?)? {
        guard let uid = IMAPParser.parseNumber(in: firstLine, key: "UID"),
              let literalSize = IMAPParser.parseLiteralSize(firstLine)
        else {
            return nil
        }
        let block = try await connection.readBytes(literalSize)
        _ = try await connection.readLine()
        return (uid, EmailBodyPreviewSanitizer.preview(from: block))
    }
}
