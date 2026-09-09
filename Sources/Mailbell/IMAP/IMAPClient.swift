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
        case staleMailboxGeneration(expected: Int, actual: Int)

        var errorDescription: String? {
            switch self {
            case let .authFailed(detail): "IMAP authentication failed: \(detail)"
            case let .selectFailed(detail): "IMAP SELECT failed: \(detail)"
            case let .unexpected(detail): "Unexpected IMAP response: \(detail)"
            case let .invalidUID(uid): "Invalid IMAP UID: \(uid)"
            case let .staleMailboxGeneration(expected, actual):
                "The mailbox was rebuilt (UIDVALIDITY \(expected) is now \(actual)), "
                    + "so this message can no longer be acted on. Reconnect and try again."
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

    let connection: any IMAPClientTransport
    private var tagCounter = 0
    static let headerFields = "BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)]"
    static let bodyPreviewBytes = 8192

    init(host: String = "imap.gmail.com", port: UInt16 = 993) {
        connection = IMAPConnection(host: host, port: port)
    }

    init(connection: any IMAPClientTransport) {
        self.connection = connection
    }

    func nextTag() -> String {
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

    /// The generation of the mailbox currently selected on this connection.
    /// Read actions check it, so a STORE cannot land on a reused UID.
    private(set) var selectedUIDValidity: Int?

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
                selectedUIDValidity = state.uidValidity
                return state
            }
            if line.hasPrefix("\(tag) NO") || line.hasPrefix("\(tag) BAD") {
                selectedUIDValidity = nil
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
    private static func quotedString(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func isFlagFetch(_ line: String) -> Bool {
        let uppercased = line.uppercased()
        return line.hasPrefix("* ") && uppercased.contains("FETCH") && uppercased.contains("FLAGS")
    }

    func parseFetch(_ firstLine: String) async throws -> MessageHeader? {
        guard let literalSize = IMAPParser.parseLiteralSize(firstLine) else {
            return nil
        }
        let block = try await connection.readBytes(literalSize)
        let trailingLine = try await connection.readLine()
        return IMAPParser.parseFetch(firstLine: firstLine, trailingLine: trailingLine, headerBlock: block)
    }

    func parseBodyPreviewFetch(_ firstLine: String) async throws -> (uid: Int, preview: String?)? {
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
