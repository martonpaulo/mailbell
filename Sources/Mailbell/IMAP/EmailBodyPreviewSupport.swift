import Foundation
import SwiftSoup

enum PreviewTokenReplacer {
    static func replaceTokens(
        in text: String,
        urlMarker: String,
        imageMarker: String,
        attachmentMarker: String
    ) -> String {
        var result = text
        result = replacing(
            pattern: #"(?i)\bdata:image/[a-z0-9.+-]+;base64,[A-Za-z0-9+/_=-]+"#,
            in: result,
            with: " \(imageMarker) "
        )
        result = replacing(pattern: #"(?i)\bcid:[^\s<>"']+"#, in: result, with: " \(imageMarker) ")
        result = replacing(
            pattern: #"(?i)\b(?:https?://|www\.)[^\s<>"'()\[\]{}]+"#,
            in: result,
            with: " \(urlMarker) "
        )
        result = replacing(pattern: #"\(\s*\[URL\]\s*\)"#, in: result, with: " \(urlMarker) ")
        result = replacing(pattern: #"<\s*\[URL\]\s*>"#, in: result, with: " \(urlMarker) ")
        result = replacing(pattern: #"\[\s*\[URL\]\s*\]"#, in: result, with: " \(urlMarker) ")
        result = replacing(pattern: #"(?:\s*\[URL\]\s*){2,}"#, in: result, with: " \(urlMarker) ")
        result = replacing(pattern: #"(?:\s*\[IMG\]\s*){2,}"#, in: result, with: " \(imageMarker) ")
        result = replacing(pattern: #"(?:\s*\[ATT\]\s*){2,}"#, in: result, with: " \(attachmentMarker) ")
        return result
    }

    private static func replacing(pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}

enum MIMEBodyPreviewNormalizer {
    static func replaceNonTextParts(
        from rawText: String,
        imageMarker: String,
        attachmentMarker: String
    ) -> String {
        let normalized = rawText.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return rawText }

        var output: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            guard isBoundaryLine(line) else {
                output.append(line)
                index += 1
                continue
            }

            output.append(line)
            index += 1

            let headerStart = index
            var headerLines: [String] = []
            while index < lines.count {
                let candidate = lines[index]
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    index += 1
                    break
                }
                guard isMIMEPartHeader(candidate) || isHeaderContinuation(candidate) else {
                    break
                }
                headerLines.append(candidate)
                index += 1
            }

            guard !headerLines.isEmpty else {
                index = headerStart
                continue
            }

            let headers = MIMEPartHeaders(lines: headerLines)
            if let marker = previewMarker(
                for: headers,
                imageMarker: imageMarker,
                attachmentMarker: attachmentMarker
            ) {
                output.append("")
                output.append(marker)
                while index < lines.count, !isBoundaryLine(lines[index]) {
                    index += 1
                }
                continue
            }

            output.append(contentsOf: headerLines)
            output.append("")
        }

        return output.joined(separator: "\n")
    }

    private static func isBoundaryLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("--")
    }

    private static func isHeaderContinuation(_ line: String) -> Bool {
        line.first == " " || line.first == "\t"
    }

    private static func isMIMEPartHeader(_ line: String) -> Bool {
        let lowercased = line.trimmingCharacters(in: .whitespaces).lowercased()
        return lowercased.hasPrefix("content-type:")
            || lowercased.hasPrefix("content-transfer-encoding:")
            || lowercased.hasPrefix("content-disposition:")
            || lowercased.hasPrefix("content-id:")
            || lowercased.hasPrefix("mime-version:")
    }

    private static func previewMarker(
        for headers: MIMEPartHeaders,
        imageMarker: String,
        attachmentMarker: String
    ) -> String? {
        guard let mediaType = headers.mediaType else { return nil }
        if mediaType.hasPrefix("image/") {
            return imageMarker
        }
        if headers.contentDisposition.contains("attachment") {
            return attachmentMarker
        }
        if mediaType.hasPrefix("text/") || mediaType.hasPrefix("multipart/") {
            return nil
        }
        return attachmentMarker
    }
}

private struct MIMEPartHeaders {
    let values: [String: String]

    init(lines: [String]) {
        var values: [String: String] = [:]
        var currentName: String?

        for line in lines {
            if Self.isHeaderContinuation(line), let currentName {
                let continuation = line.trimmingCharacters(in: .whitespacesAndNewlines)
                values[currentName, default: ""] += " \(continuation)"
                continue
            }

            guard let separator = line.firstIndex(of: ":") else {
                currentName = nil
                continue
            }

            let name = line[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            values[name] = value
            currentName = name
        }

        self.values = values
    }

    var mediaType: String? {
        values["content-type"]?
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var contentDisposition: String {
        values["content-disposition"]?.lowercased() ?? ""
    }

    private static func isHeaderContinuation(_ line: String) -> Bool {
        line.first == " " || line.first == "\t"
    }
}

enum Base64PreviewDecoder {
    private static let minimumFoldWidth = 32

    static func decodePayloadsIfUseful(_ text: String, imageMarker: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var block: [String] = []

        func flushBlock() {
            guard !block.isEmpty else { return }
            if let replacement = decodedPreviewReplacement(for: block, imageMarker: imageMarker) {
                output.append(replacement)
            } else {
                output.append(contentsOf: block)
            }
            block.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if isBase64PayloadLine(trimmed) {
                block.append(trimmed)
            } else if let folded = foldedBase64Chunks(in: trimmed) {
                // A transport that collapsed the CRLF folds leaves the whole
                // payload on one line, separated by spaces.
                flushBlock()
                block.append(contentsOf: folded)
                flushBlock()
            } else {
                flushBlock()
                output.append(line)
            }
        }

        flushBlock()
        return output.joined(separator: "\n")
    }

    private static func isBase64PayloadLine(_ line: String) -> Bool {
        guard line.count >= 16 else { return false }
        return containsPattern(#"^[A-Za-z0-9+/_-]+={0,2}$"#, in: line)
    }

    /// Base64 folded on spaces rather than CRLF. Ordinary prose is also made of
    /// alphabet characters and spaces, so this demands the shape only a folded
    /// payload has: several chunks of one fixed, wide width. A sentence never
    /// has uniform 32-character words.
    private static func foldedBase64Chunks(in line: String) -> [String]? {
        let chunks = line.split(separator: " ").map(String.init)
        guard chunks.count >= 2 else { return nil }
        guard chunks.allSatisfy({ containsPattern(#"^[A-Za-z0-9+/_-]+={0,2}$"#, in: $0) }) else { return nil }

        let width = chunks[0].count
        guard width >= minimumFoldWidth else { return nil }
        guard chunks.dropLast().allSatisfy({ $0.count == width }) else { return nil }
        guard let last = chunks.last, last.count <= width else { return nil }
        return chunks
    }

    private static func decodedPreviewReplacement(for lines: [String], imageMarker: String) -> String? {
        let joined = lines.joined()
        guard joined.count >= 24 else { return nil }

        let standardBase64 = joined
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // A bounded BODY.PEEK slice cuts the payload anywhere. One leftover
        // character encodes nothing and admits no valid padding, so dropping it
        // is what makes a truncated block decodable instead of leaking whole.
        let aligned = standardBase64.count % 4 == 1
            ? String(standardBase64.dropLast())
            : standardBase64
        let remainder = aligned.count % 4
        let padded = remainder == 0
            ? aligned
            : aligned + String(repeating: "=", count: 4 - remainder)

        guard let data = Data(base64Encoded: padded, options: [.ignoreUnknownCharacters]) else {
            return nil
        }
        if isKnownImageData(data) {
            return imageMarker
        }
        guard isMostlyPrintableText(data),
              let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else {
            return nil
        }

        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard decodedTextLooksUseful(trimmed) else { return nil }
        return trimmed
    }

    private static func isKnownImageData(_ data: Data) -> Bool {
        let bytes = Array(data.prefix(12))
        return bytes.starts(with: [0x89, 0x50, 0x4E, 0x47])
            || bytes.starts(with: [0xFF, 0xD8, 0xFF])
            || bytes.starts(with: [0x47, 0x49, 0x46, 0x38])
            || bytes.starts(with: [0x52, 0x49, 0x46, 0x46])
            && bytes.dropFirst(8).starts(with: [0x57, 0x45, 0x42, 0x50])
    }

    private static func isMostlyPrintableText(_ data: Data) -> Bool {
        let bytes = Array(data)
        guard !bytes.isEmpty else { return false }
        let controlCount = bytes.filter { byte in
            byte < 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D
        }.count
        return Double(controlCount) / Double(bytes.count) < 0.05
    }

    private static func decodedTextLooksUseful(_ text: String) -> Bool {
        guard text.count >= 4 else { return false }
        return text.contains(" ")
            || containsPattern(#"(?is)</?[A-Za-z][A-Za-z0-9:-]*(?:\s+[^<>]*)?/?>"#, in: text)
            || containsPattern(#"(?i)\b(?:https?://|www\.)"#, in: text)
            || containsPattern(#"[.!?]"#, in: text)
    }

    private static func containsPattern(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}

/// Turning an HTML message part into plain preview text: dropping the parts a
/// reader never sees, marking images, and falling back to the raw text when the
/// slice cannot be parsed. Separated from the sanitizer pipeline, which decides
/// the order of stages rather than how any one of them works.
enum HTMLPreviewTextExtractor {
    private static let imageMarker = "[IMG]"

    static func decodeIfNeeded(
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

    static func extractText(from text: String) throws -> String {
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

        for element in try document.select("img, svg").array() {
            try element.before(" \(imageMarker) ")
            try element.remove()
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
