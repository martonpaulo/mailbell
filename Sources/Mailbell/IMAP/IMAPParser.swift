import Foundation

enum IMAPParser {
    static func parseFetch(firstLine: String, headerBlock: Data) -> MessageHeader? {
        guard parseLiteralSize(firstLine) != nil else { return nil }

        let uid = parseNumber(in: firstLine, key: "UID") ?? 0
        let msgid = parseToken(in: firstLine, key: "X-GM-MSGID")
        let thrid = parseToken(in: firstLine, key: "X-GM-THRID")
        let raw = String(bytes: headerBlock, encoding: .utf8) ?? ""
        let fields = parseHeaderFields(raw)

        return MessageHeader(
            uid: uid,
            from: MIMEHeaderDecoder.decode(fields["from"] ?? "Unknown sender"),
            subject: MIMEHeaderDecoder.decode(fields["subject"] ?? "(no subject)"),
            date: fields["date"] ?? "",
            gmThreadId: thrid,
            gmMessageId: msgid,
            messageId: fields["message-id"]
        )
    }

    static func parseUntagged(_ line: String, suffix: String) -> Int? {
        guard line.hasPrefix("* ") else { return nil }
        let parts = line.dropFirst(2).split(separator: " ")
        guard parts.count >= 2, parts[1].uppercased() == suffix,
              let value = Int(parts[0]) else { return nil }
        return value
    }

    static func parseBracket(_ line: String, key: String) -> Int? {
        guard let range = line.range(of: "[\(key) ") else { return nil }
        let tail = line[range.upperBound...]
        let digits = tail.prefix { $0.isNumber }
        return Int(digits)
    }

    static func parseSearchUIDs(_ line: String) -> [Int]? {
        guard line.hasPrefix("* ") else { return nil }
        let parts = line.dropFirst(2).split(separator: " ")
        guard let command = parts.first, command.uppercased() == "SEARCH" else { return nil }
        return parts.dropFirst().compactMap { Int($0) }
    }

    static func parseSpecialUseMailbox(_ line: String, flag: String) -> String? {
        let uppercasedLine = line.uppercased()
        guard uppercasedLine.hasPrefix("* LIST "),
              uppercasedLine.contains(flag.uppercased())
        else {
            return nil
        }
        return parseLastQuotedString(in: line)
    }

    static func parseNumber(in line: String, key: String) -> Int? {
        guard let range = line.range(of: "\(key) ") else { return nil }
        let tail = line[range.upperBound...]
        let digits = tail.prefix { $0.isNumber }
        return Int(digits)
    }

    static func parseToken(in line: String, key: String) -> String? {
        guard let range = line.range(of: "\(key) ") else { return nil }
        let tail = line[range.upperBound...]
        let token = tail.prefix { $0.isNumber || $0.isLetter }
        return token.isEmpty ? nil : String(token)
    }

    static func parseLiteralSize(_ line: String) -> Int? {
        guard let open = line.range(of: "{", options: .backwards),
              let close = line.range(of: "}", options: .backwards),
              open.upperBound < close.lowerBound else { return nil }
        return Int(line[open.upperBound ..< close.lowerBound])
    }

    private static func parseLastQuotedString(in line: String) -> String? {
        var quotedStrings: [String] = []
        var current = ""
        var isInsideQuotes = false
        var isEscaped = false

        for character in line {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = isInsideQuotes
                if !isInsideQuotes {
                    current.append(character)
                }
                continue
            }
            if character == "\"" {
                if isInsideQuotes {
                    quotedStrings.append(current)
                    current = ""
                }
                isInsideQuotes.toggle()
                continue
            }
            if isInsideQuotes {
                current.append(character)
            }
        }

        return quotedStrings.last
    }

    static func parseHeaderFields(_ raw: String) -> [String: String] {
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
                currentValue += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                commit()
                currentKey = String(line[line.startIndex ..< colon])
                currentValue = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        commit()
        return fields
    }
}
