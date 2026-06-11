import Foundation
import os

enum Log {
    private static let logger = os.Logger(subsystem: AppIdentity.bundleIdentifier, category: "app")
    private static let sensitivePatterns: [(pattern: String, replacement: String)] = [
        (
            #"(?i)\b(access_token|refresh_token|client_secret|code_verifier|code)\b\s*[:=]\s*["']?[^"',&\s}\]]+"#,
            "$1=<redacted>"
        ),
        (
            #"(?i)\b(Bearer\s+)[A-Za-z0-9._~+/=-]+"#,
            "$1<redacted>"
        )
    ]

    static func info(_ message: @autoclosure () -> String) {
        let text = redact(message())
        logger.info("\(text, privacy: .public)")
    }

    static func error(_ message: @autoclosure () -> String) {
        let text = redact(message())
        logger.error("\(text, privacy: .public)")
    }

    static func redact(_ message: String) -> String {
        sensitivePatterns.reduce(message) { current, rule in
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else {
                return current
            }
            let range = NSRange(current.startIndex..<current.endIndex, in: current)
            return regex.stringByReplacingMatches(
                in: current,
                options: [],
                range: range,
                withTemplate: rule.replacement
            )
        }
    }
}
