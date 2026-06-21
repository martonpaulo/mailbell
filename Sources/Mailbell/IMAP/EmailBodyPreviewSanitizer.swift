import Foundation

enum EmailBodyPreviewSanitizer {
    static let maximumPreviewLength = 240

    static func preview(from data: Data, limit: Int = maximumPreviewLength) -> String? {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        return preview(from: text, limit: limit)
    }

    static func preview(from rawText: String, limit: Int = maximumPreviewLength) -> String? {
        let withoutMIMEHeaders = removeMIMEPartHeaders(from: rawText)
        let quotedPrintableDecoded = decodeQuotedPrintable(withoutMIMEHeaders)
        let htmlStripped = stripHTML(from: quotedPrintableDecoded)
        let entityDecoded = decodeHTMLEntities(in: htmlStripped)
        let punctuationTightened = replacing(pattern: "\\s+([\\.,;:!?])", in: entityDecoded, with: "$1")
        let collapsed = punctuationTightened
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return nil }
        return truncated(collapsed, limit: limit)
    }

    private static func removeMIMEPartHeaders(from rawText: String) -> String {
        let normalized = rawText.replacingOccurrences(of: "\r\n", with: "\n")
        var retained: [String] = []
        var isSkippingPartHeaders = false

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("--") {
                isSkippingPartHeaders = true
                continue
            }
            if isSkippingPartHeaders {
                if trimmed.isEmpty {
                    isSkippingPartHeaders = false
                }
                continue
            }
            if isMIMEPartHeader(line) {
                continue
            }
            retained.append(line)
        }

        return retained.joined(separator: "\n")
    }

    private static func isMIMEPartHeader(_ line: String) -> Bool {
        let lowercased = line.trimmingCharacters(in: .whitespaces).lowercased()
        return lowercased.hasPrefix("content-type:")
            || lowercased.hasPrefix("content-transfer-encoding:")
            || lowercased.hasPrefix("content-disposition:")
            || lowercased.hasPrefix("mime-version:")
    }

    private static func decodeQuotedPrintable(_ text: String) -> String {
        let bytes = Array(text.utf8)
        var decoded: [UInt8] = []
        var index = 0
        let equals = UInt8(ascii: "=")
        let carriageReturn = UInt8(ascii: "\r")
        let lineFeed = UInt8(ascii: "\n")

        while index < bytes.count {
            let byte = bytes[index]
            if byte == equals {
                if index + 1 < bytes.count, bytes[index + 1] == lineFeed {
                    index += 2
                    continue
                }
                if index + 2 < bytes.count,
                   bytes[index + 1] == carriageReturn,
                   bytes[index + 2] == lineFeed {
                    index += 3
                    continue
                }
                if index + 2 < bytes.count,
                   let high = hexValue(bytes[index + 1]),
                   let low = hexValue(bytes[index + 2]) {
                    decoded.append(high * 16 + low)
                    index += 3
                    continue
                }
            }
            decoded.append(byte)
            index += 1
        }

        return String(data: Data(decoded), encoding: .utf8) ?? text
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        let zero = UInt8(ascii: "0")
        let nine = UInt8(ascii: "9")
        let uppercaseA = UInt8(ascii: "A")
        let uppercaseF = UInt8(ascii: "F")
        let lowercaseA = UInt8(ascii: "a")
        let lowercaseF = UInt8(ascii: "f")

        switch byte {
        case zero ... nine:
            return byte - zero
        case uppercaseA ... uppercaseF:
            return byte - uppercaseA + 10
        case lowercaseA ... lowercaseF:
            return byte - lowercaseA + 10
        default:
            return nil
        }
    }

    private static func stripHTML(from text: String) -> String {
        var result = text
        result = replacing(pattern: "(?is)<script[^>]*>.*?</script>", in: result, with: " ")
        result = replacing(pattern: "(?is)<style[^>]*>.*?</style>", in: result, with: " ")
        result = replacing(pattern: "(?is)<br\\s*/?>", in: result, with: "\n")
        result = replacing(pattern: "(?is)</p\\s*>", in: result, with: "\n")
        result = replacing(pattern: "(?is)<[^>]+>", in: result, with: " ")
        return result
    }

    private static func replacing(pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    private static func decodeHTMLEntities(in text: String) -> String {
        var decoded = text
        let namedEntities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'"
        ]
        for (entity, replacement) in namedEntities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }
        return decodeNumericEntities(in: decoded)
    }

    private static func decodeNumericEntities(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else {
            return text
        }

        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex ..< text.endIndex, in: text))
        for match in matches.reversed() {
            guard let entityRange = Range(match.range(at: 0), in: result),
                  let valueRange = Range(match.range(at: 1), in: result)
            else {
                continue
            }
            let rawValue = result[valueRange]
            let radix = rawValue.first == "x" ? 16 : 10
            let digits = rawValue.first == "x" ? rawValue.dropFirst() : rawValue[...]
            guard let scalarValue = UInt32(String(digits), radix: radix),
                  let scalar = UnicodeScalar(scalarValue)
            else {
                continue
            }
            result.replaceSubrange(entityRange, with: String(Character(scalar)))
        }
        return result
    }

    private static func truncated(_ text: String, limit: Int) -> String {
        guard limit > 0, text.count > limit else { return text }
        let limitIndex = text.index(text.startIndex, offsetBy: limit)
        let prefix = text[..<limitIndex]
        if let wordBoundary = prefix.lastIndex(where: { $0.isWhitespace }),
           text.distance(from: prefix.startIndex, to: wordBoundary) > limit / 2 {
            return String(prefix[..<wordBoundary]) + "..."
        }
        return String(prefix) + "..."
    }
}
