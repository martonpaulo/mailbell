import Foundation
import SwiftSoup

enum EmailBodyPreviewSanitizer {
    static let maximumPreviewLength = 240
    private static let maximumLineLength = 80
    private static let maximumLineCount = 3

    static func preview(from data: Data, limit: Int = maximumPreviewLength) -> String? {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        return preview(from: text, limit: limit)
    }

    static func preview(
        from rawText: String,
        limit: Int = maximumPreviewLength,
        htmlTextExtractor: (String) throws -> String = extractHTMLText
    ) -> String? {
        let withoutMIMEHeaders = removeMIMEPartHeaders(from: rawText)
        let quotedPrintableDecoded = decodeQuotedPrintable(withoutMIMEHeaders)
        let htmlDecoded = decodeHTMLIfNeeded(quotedPrintableDecoded, htmlTextExtractor: htmlTextExtractor)
        let withoutMIMEArtifacts = removeMIMEArtifacts(from: htmlDecoded)
        let withoutURLs = replacing(
            pattern: #"(?i)\b(?:https?://|www\.)[^\s<>"']+"#,
            in: withoutMIMEArtifacts,
            with: "URL"
        )
        let punctuationTightened = replacing(pattern: "\\s+([\\.,;:!?])", in: withoutURLs, with: "$1")
        let collapsed = punctuationTightened
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return nil }
        return wrappedPreview(truncated(collapsed, limit: limit))
    }

    private static func removeMIMEPartHeaders(from rawText: String) -> String {
        let normalized = rawText.replacingOccurrences(of: "\r\n", with: "\n")
        var retained: [String] = []
        var isSkippingPartHeaders = false
        var isSkippingFoldedHeader = false

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("--") {
                isSkippingPartHeaders = true
                isSkippingFoldedHeader = false
                continue
            }
            if isSkippingPartHeaders {
                if trimmed.isEmpty {
                    isSkippingPartHeaders = false
                }
                continue
            }
            if isSkippingFoldedHeader, line.first == " " || line.first == "\t" {
                continue
            }
            isSkippingFoldedHeader = false
            if isMIMEPartHeader(line) {
                isSkippingFoldedHeader = true
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
            || lowercased.hasPrefix("content-id:")
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

    private static func removeMIMEArtifacts(from text: String) -> String {
        var result = text
        result = replacing(pattern: #"(?im)^--[A-Za-z0-9'()+_,./:=?-]+--?$"#, in: result, with: " ")
        result = replacing(pattern: #"(?im)^Content-[A-Za-z-]+:.*$"#, in: result, with: " ")
        result = replacing(pattern: #"(?im)^MIME-Version:.*$"#, in: result, with: " ")
        result = replacing(
            pattern: #"(?i)\bThis is a multi[-\s]?part message in MIME format\.?\s*"#,
            in: result,
            with: " "
        )
        result = replacing(pattern: #"(?i)\bThis message is in MIME format\.?\s*"#, in: result, with: " ")
        result = replacing(pattern: #"(?im)^.*MIME part.*$"#, in: result, with: " ")
        result = replacing(pattern: #"(?im)^charset="?[-A-Za-z0-9_]+"?.*$"#, in: result, with: " ")
        result = replacing(pattern: #"(?im)^boundary="?[-A-Za-z0-9'()+_,./:=?]+"?.*$"#, in: result, with: " ")
        result = replacing(pattern: #"(?im)^multipart/[-A-Za-z0-9.+]+.*$"#, in: result, with: " ")
        return result
    }

    private static func replacing(pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
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

    private static func wrappedPreview(_ text: String) -> String {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return text }

        var lines: [String] = []
        var current = ""

        for word in words {
            if lines.count == maximumLineCount - 1 {
                current = current.isEmpty ? word : "\(current) \(word)"
                continue
            }

            let candidate = current.isEmpty ? word : "\(current) \(word)"
            if candidate.count <= maximumLineLength || current.isEmpty {
                current = candidate
                continue
            }

            lines.append(current)
            current = word
        }

        if !current.isEmpty {
            lines.append(current)
        }

        if lines.count <= maximumLineCount {
            return lines.joined(separator: "\n")
        }

        let retained = lines.prefix(maximumLineCount - 1)
        let remainder = lines.dropFirst(maximumLineCount - 1).joined(separator: " ")
        return (Array(retained) + [truncated(remainder, limit: maximumLineLength)])
            .joined(separator: "\n")
    }

    private static func decodeHTMLIfNeeded(
        _ text: String,
        htmlTextExtractor: (String) throws -> String
    ) -> String {
        guard containsHTMLSignal(text) else { return text }
        do {
            return try htmlTextExtractor(text)
        } catch {
            return text
        }
    }

    private static func extractHTMLText(from text: String) throws -> String {
        let document = try SwiftSoup.parseHTML(text)
        try document.select("script, style, noscript, template, head, meta, link").remove()
        try document.select("[hidden], [aria-hidden=true]").remove()

        for element in try document.select("[style]").array() {
            let style = try element.attr("style")
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
            if style.contains("display:none")
                || style.contains("visibility:hidden")
                || style.contains("opacity:0") {
                try element.remove()
            }
        }

        if let body = document.body() {
            return try body.text()
        }
        return try document.text()
    }

    private static func containsHTMLSignal(_ text: String) -> Bool {
        containsPattern(#"(?is)</?[A-Za-z][A-Za-z0-9:-]*(?:\s+[^<>]*)?/?>"#, in: text)
            || containsPattern(#"&#(?:x[0-9A-Fa-f]+|[0-9]+);|&[A-Za-z][A-Za-z0-9]+;"#, in: text)
    }

    private static func containsPattern(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
