import Foundation
import os

/// The one logging owner: a logger per area, all under the bundle identifier.
///
/// Every interpolated value passes through `redact` first. Account addresses,
/// senders, subjects, message identifiers and error details are interpolated
/// `.private`; fixed text, counts and states are `.public`.
///
/// Nonisolated: logged from every queue and task.
nonisolated enum Log {
    private static let subsystem = AppIdentity.bundleIdentifier

    static let app = Logger(subsystem: subsystem, category: "app")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let imap = Logger(subsystem: subsystem, category: "imap")
    static let monitor = Logger(subsystem: subsystem, category: "monitor")
    static let notify = Logger(subsystem: subsystem, category: "notify")
    static let webmail = Logger(subsystem: subsystem, category: "webmail")

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

    /// The technical detail of an error, for the log only. User-facing error
    /// text carries no detail, so the log is where the cause is kept.
    static func detail(_ error: any Error) -> String {
        redact(String(reflecting: error))
    }

    static func redact(_ message: String) -> String {
        sensitivePatterns.reduce(message) { current, rule in
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else {
                return current
            }
            let range = NSRange(current.startIndex ..< current.endIndex, in: current)
            return regex.stringByReplacingMatches(
                in: current,
                options: [],
                range: range,
                withTemplate: rule.replacement
            )
        }
    }
}
