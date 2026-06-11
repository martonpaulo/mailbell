import Foundation

/// High-level Gmail IMAP client: XOAUTH2 auth, mailbox select, IDLE, and header
/// fetch. Built on top of the line-oriented `IMAPConnection`.
final class IMAPClient {
    enum IMAPError: Error, LocalizedError {
        case authFailed(String)
        case selectFailed(String)
        case unexpected(String)

        var errorDescription: String? {
            switch self {
            case .authFailed(let detail): return "IMAP authentication failed: \(detail)"
            case .selectFailed(let detail): return "IMAP SELECT failed: \(detail)"
            case .unexpected(let detail): return "Unexpected IMAP response: \(detail)"
            }
        }
    }

    enum IdleEvent {
        case newMessages(exists: Int)
        case timedOut
    }

    /// Ensures `DONE` is sent at most once per IDLE, even though both the timeout
    /// task and the read loop may race to end the IDLE.
    private actor DoneGate {
        private var claimed = false
        func claim() -> Bool {
            if claimed { return false }
            claimed = true
            return true
        }
    }

    private let connection: IMAPConnection
    private var tagCounter = 0

    init(host: String = "imap.gmail.com", port: UInt16 = 993) {
        connection = IMAPConnection(host: host, port: port)
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
            if line.hasPrefix("\(tag) OK") { return }
            if line.hasPrefix("\(tag) NO") || line.hasPrefix("\(tag) BAD") {
                throw IMAPError.authFailed(line)
            }
        }
    }

    // MARK: - Select

    @discardableResult
    func selectInbox() async throws -> MailboxState {
        let tag = nextTag()
        try await connection.send("\(tag) SELECT INBOX")
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
            if line.hasPrefix("\(tag) OK") { return state }
            if line.hasPrefix("\(tag) NO") || line.hasPrefix("\(tag) BAD") {
                throw IMAPError.selectFailed(line)
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
        let connection = self.connection

        let timeoutTask = Task { [connection, gate] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if await gate.claim() {
                try? await connection.sendRaw("DONE\r\n")
            }
        }
        defer { timeoutTask.cancel() }

        var sawNewMessages = false
        while true {
            let line = try await connection.readLine()
            if IMAPParser.parseUntagged(line, suffix: "EXISTS") != nil {
                sawNewMessages = true
                if await gate.claim() {
                    try? await connection.sendRaw("DONE\r\n")
                }
            }
            if line.hasPrefix("\(tag) OK") {
                return sawNewMessages ? .newMessages(exists: 0) : .timedOut
            }
            if line.hasPrefix("\(tag) NO") || line.hasPrefix("\(tag) BAD") {
                throw IMAPError.unexpected(line)
            }
        }
    }

    // MARK: - Fetch headers

    /// Fetches headers for UIDs in `[fromUID, *]` (i.e. UID >= fromUID).
    func fetchHeaders(fromUID: Int) async throws -> [MessageHeader] {
        let tag = nextTag()
        let fields = "BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)]"
        try await connection.send("\(tag) UID FETCH \(fromUID):* (UID X-GM-THRID \(fields))")

        var headers: [MessageHeader] = []
        while true {
            let line = try await connection.readLine()
            if line.hasPrefix("* "), line.uppercased().contains("FETCH") {
                if let header = try await parseFetch(line) {
                    headers.append(header)
                }
                continue
            }
            if line.hasPrefix("\(tag) OK") { break }
            if line.hasPrefix("\(tag) NO") || line.hasPrefix("\(tag) BAD") {
                throw IMAPError.unexpected(line)
            }
        }
        return headers
    }

    private func parseFetch(_ firstLine: String) async throws -> MessageHeader? {
        guard let literalSize = IMAPParser.parseLiteralSize(firstLine) else {
            return nil
        }
        let block = try await connection.readBytes(literalSize)
        _ = try await connection.readLine()
        return IMAPParser.parseFetch(firstLine: firstLine, headerBlock: block)
    }
}
