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
            if let exists = parseUntagged(line, suffix: "EXISTS") {
                state.exists = exists
            }
            if let uidValidity = parseBracket(line, key: "UIDVALIDITY") {
                state.uidValidity = uidValidity
            }
            if let uidNext = parseBracket(line, key: "UIDNEXT") {
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
        let sendDone: () async -> Void = { [weak self] in
            guard let self else { return }
            if await gate.claim() {
                try? await self.connection.sendRaw("DONE\r\n")
            }
        }

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if !Task.isCancelled { await sendDone() }
        }
        defer { timeoutTask.cancel() }

        var sawNewMessages = false
        while true {
            let line = try await connection.readLine()
            if parseUntagged(line, suffix: "EXISTS") != nil {
                sawNewMessages = true
                await sendDone()
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
        let uid = parseNumber(in: firstLine, key: "UID") ?? 0
        let thrid = parseToken(in: firstLine, key: "X-GM-THRID")

        // The header block is delivered as a literal `{n}` at the end of the line.
        guard let literalSize = parseLiteralSize(firstLine) else {
            return nil
        }
        let block = try await connection.readBytes(literalSize)
        // Consume the rest of the FETCH response up to its closing line.
        _ = try await connection.readLine()

        let raw = String(bytes: block, encoding: .utf8) ?? ""
        let fields = parseHeaderFields(raw)
        return MessageHeader(
            uid: uid,
            from: MIMEHeaderDecoder.decode(fields["from"] ?? "Unknown sender"),
            subject: MIMEHeaderDecoder.decode(fields["subject"] ?? "(no subject)"),
            date: fields["date"] ?? "",
            gmThreadId: thrid
        )
    }

    // MARK: - Parsing helpers

    private func parseUntagged(_ line: String, suffix: String) -> Int? {
        // e.g. "* 12 EXISTS"
        guard line.hasPrefix("* ") else { return nil }
        let parts = line.dropFirst(2).split(separator: " ")
        guard parts.count >= 2, parts[1].uppercased() == suffix,
              let value = Int(parts[0]) else { return nil }
        return value
    }

    private func parseBracket(_ line: String, key: String) -> Int? {
        // e.g. "* OK [UIDVALIDITY 12345] ..."
        guard let range = line.range(of: "[\(key) ") else { return nil }
        let tail = line[range.upperBound...]
        let digits = tail.prefix { $0.isNumber }
        return Int(digits)
    }

    private func parseNumber(in line: String, key: String) -> Int? {
        guard let range = line.range(of: "\(key) ") else { return nil }
        let tail = line[range.upperBound...]
        let digits = tail.prefix { $0.isNumber }
        return Int(digits)
    }

    private func parseToken(in line: String, key: String) -> String? {
        guard let range = line.range(of: "\(key) ") else { return nil }
        let tail = line[range.upperBound...]
        let token = tail.prefix { $0.isNumber || $0.isLetter }
        return token.isEmpty ? nil : String(token)
    }

    private func parseLiteralSize(_ line: String) -> Int? {
        guard let open = line.range(of: "{", options: .backwards),
              let close = line.range(of: "}", options: .backwards),
              open.upperBound < close.lowerBound else { return nil }
        return Int(line[open.upperBound..<close.lowerBound])
    }

    private func parseHeaderFields(_ raw: String) -> [String: String] {
        var fields: [String: String] = [:]
        var currentKey: String?
        var currentValue = ""

        func commit() {
            if let key = currentKey {
                fields[key.lowercased()] = currentValue.trimmingCharacters(in: .whitespaces)
            }
        }

        for rawLine in raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.first == " " || line.first == "\t" {
                // Folded continuation of the previous header.
                currentValue += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                commit()
                currentKey = String(line[line.startIndex..<colon])
                currentValue = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        commit()
        return fields
    }
}
