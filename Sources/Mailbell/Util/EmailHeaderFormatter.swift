import Foundation

enum EmailHeaderFormatter {
    static func title(for header: MessageHeader) -> String {
        let title = header.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "(no subject)" : title
    }

    static func senderTitle(from rawSender: String) -> String {
        let sender = rawSender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sender.isEmpty else { return "Unknown sender" }

        guard let angleStart = sender.firstIndex(of: "<"),
              let angleEnd = sender[angleStart...].firstIndex(of: ">")
        else {
            return sender.trimmingMatchingQuotes()
        }

        let displayName = sender[..<angleStart]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingMatchingQuotes()
        if !displayName.isEmpty {
            return displayName
        }

        let email = sender[sender.index(after: angleStart) ..< angleEnd]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? "Unknown sender" : email
    }

    static func senderDetail(from rawSender: String) -> String {
        let sender = rawSender.trimmingCharacters(in: .whitespacesAndNewlines)
        return sender.isEmpty ? "Unknown sender" : sender
    }

    static func timeText(for header: MessageHeader) -> String {
        let rawDate = header.date.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawDate.isEmpty else { return "Time unknown" }
        guard let date = parseMailDate(rawDate) else { return rawDate }
        return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
    }

    private static func parseMailDate(_ rawDate: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: rawDate) {
                return date
            }
        }
        return nil
    }
}

private extension StringProtocol {
    func trimmingMatchingQuotes() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              let first = trimmed.first,
              let last = trimmed.last,
              first == last,
              first == "\"" || first == "'"
        else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast())
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
