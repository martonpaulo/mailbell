import Foundation
@preconcurrency import UserNotifications

enum EmailNotificationContentBuilder {
    static func build(
        header: MessageHeader,
        webmailURL: URL,
        accountID: UUID?
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = senderTitle(from: header.from)
        content.body = header.subject
        content.sound = .default

        var userInfo: [String: String] = [
            notificationWebmailURLKey: webmailURL.absoluteString
        ]
        if let accountID {
            userInfo[notificationAccountIDKey] = accountID.uuidString
        }
        content.userInfo = userInfo
        return content
    }

    static func senderTitle(from rawSender: String) -> String {
        let sender = rawSender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sender.isEmpty else { return "Unknown sender" }

        guard let angleStart = sender.firstIndex(of: "<"),
              let angleEnd = sender[angleStart...].firstIndex(of: ">") else {
            return sender.trimmingMatchingQuotes()
        }

        let displayName = sender[..<angleStart]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingMatchingQuotes()
        if !displayName.isEmpty {
            return displayName
        }

        let email = sender[sender.index(after: angleStart)..<angleEnd]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? "Unknown sender" : email
    }
}

private extension StringProtocol {
    func trimmingMatchingQuotes() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              let first = trimmed.first,
              let last = trimmed.last,
              first == last,
              first == "\"" || first == "'" else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast())
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
