import Foundation

/// A bounded `BODY.PEEK[TEXT]` slice can hand the sanitizer a stylesheet that
/// has lost its enclosing `<style>` element — the opening tag fell outside the
/// slice, or the MIME part carrying it was stripped. SwiftSoup then has nothing
/// to remove and the CSS becomes body text, which is how rules like
/// `body, table, td { font-family: Arial }` reached notifications.
///
/// Detection is by CSS *syntax*, never vocabulary: prose that happens to
/// mention body, style, or font-family is left alone.
enum StylesheetPreviewArtifactRemover {
    private static let ruleBlockPattern = #"(?s)[^{}<>;]{1,240}\{[^{}<>]*\}"#
    private static let declarationPattern = #"(?i)[-a-z]+\s*:\s*[^;{}]+"#
    private static let orphanBracePattern = #"(?m)^\s*[}{]\s*$"#
    /// Only the CSS at-rules, anchored at a token boundary. A bare `@[a-z]+`
    /// would swallow the domain half of an email address.
    private static let atRuleHeaderPattern =
        #"(?is)(?<![A-Za-z0-9._%+-])@(?:media|supports|font-face|import|charset"#
            + #"|keyframes|page|namespace|layer|container|property)\b[^{};<>]{0,200}\{?"#

    static func removeStylesheetArtifacts(from text: String) -> String {
        var result = removingOrphanedStylesheetPrefix(from: text)
        // Two passes: a nested at-rule leaves its outer block behind on the first.
        for _ in 0 ..< 2 {
            result = removingRuleBlocks(from: result)
        }
        result = replacing(pattern: atRuleHeaderPattern, in: result, with: " ")
        return replacing(pattern: orphanBracePattern, in: result, with: " ")
    }

    /// A closing `</style>` with no opener before it means the slice began
    /// inside the stylesheet, so everything up to that tag is CSS.
    private static func removingOrphanedStylesheetPrefix(from text: String) -> String {
        guard let closing = text.range(of: "</style", options: [.caseInsensitive]) else { return text }
        let prefix = text[text.startIndex ..< closing.lowerBound]
        guard prefix.range(of: "<style", options: [.caseInsensitive]) == nil else { return text }
        guard let tagEnd = text[closing.lowerBound...].firstIndex(of: ">") else { return text }
        return String(text[text.index(after: tagEnd)...])
    }

    private static func removingRuleBlocks(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: ruleBlockPattern) else { return text }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        var result = ""
        var cursor = text.startIndex

        for match in regex.matches(in: text, range: range) {
            guard let matched = Range(match.range, in: text),
                  isStylesheetRule(String(text[matched]))
            else {
                continue
            }
            result += text[cursor ..< matched.lowerBound] + " "
            cursor = matched.upperBound
        }

        result += text[cursor...]
        return result
    }

    /// A rule is CSS only when its braces hold declarations. That is what keeps
    /// a sentence, or a JSON-looking fragment, from being deleted as a style.
    private static func isStylesheetRule(_ candidate: String) -> Bool {
        guard let open = candidate.firstIndex(of: "{"),
              let close = candidate.lastIndex(of: "}")
        else {
            return false
        }
        let selector = candidate[candidate.startIndex ..< open]
        guard !selector.contains("\""), !selector.contains("'") else { return false }

        let declarations = String(candidate[candidate.index(after: open) ..< close])
        guard !declarations.contains("\""), !declarations.contains("'") else { return false }
        guard let regex = try? NSRegularExpression(pattern: declarationPattern) else { return false }
        let range = NSRange(declarations.startIndex ..< declarations.endIndex, in: declarations)
        return regex.firstMatch(in: declarations, range: range) != nil
    }

    private static func replacing(pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
