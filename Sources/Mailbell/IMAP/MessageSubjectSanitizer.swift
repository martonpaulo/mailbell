import Foundation
import MailbellKit

/// The subject as the review queue and notifications show it: MIME-decoded,
/// sanitized like a body preview, whitespace collapsed, at most 160 characters.
/// `IMAPClient` applies it once, when it parses a fetched header, so the header
/// that reaches MailbellKit already carries display text. It lives in the app
/// target because HTML handling goes through SwiftSoup (#80).
///
/// Nonisolated: called by IMAPClient inside MailMonitor run tasks.
nonisolated enum MessageSubjectSanitizer {
    private static let maximumLength = 160

    static func displayText(from rawSubject: String) -> String {
        let decodedSubject = MIMEHeaderDecoder.decode(rawSubject)
        return EmailBodyPreviewSanitizer.preview(
            from: decodedSubject,
            limit: maximumLength,
            htmlTextExtractor: SwiftSoupPreviewTextExtractor.extractText
        )?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ") ?? ""
    }
}
