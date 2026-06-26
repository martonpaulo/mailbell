import Foundation

enum EmailHeaderFormatter {
    private static let spamTitlePrefix = "(SPAM)"

    struct SenderIdentity: Equatable {
        let name: String
        let address: String?
    }

    static func title(for header: MessageHeader) -> String {
        let title = header.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.isEmpty ? "(no subject)" : title
        guard header.mailbox == .spam else { return resolvedTitle }
        return titleWithSpamPrefix(resolvedTitle)
    }

    static func senderTitle(from rawSender: String) -> String {
        senderIdentity(from: rawSender).name
    }

    static func senderIdentity(from rawSender: String) -> SenderIdentity {
        let sender = rawSender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sender.isEmpty else {
            return SenderIdentity(name: "Unknown sender", address: nil)
        }

        guard let angleStart = sender.firstIndex(of: "<"),
              let angleEnd = sender[angleStart...].firstIndex(of: ">")
        else {
            let name = sender.trimmingMatchingQuotes()
            return SenderIdentity(name: name, address: name.looksLikeEmailAddress ? name : nil)
        }

        let displayName = sender[..<angleStart]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingMatchingQuotes()
        let email = sender[sender.index(after: angleStart) ..< angleEnd]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !displayName.isEmpty {
            return SenderIdentity(name: displayName, address: email.nilIfEmpty)
        }

        return SenderIdentity(name: email.isEmpty ? "Unknown sender" : email, address: email.nilIfEmpty)
    }

    static func senderDetail(from rawSender: String) -> String {
        let sender = rawSender.trimmingCharacters(in: .whitespacesAndNewlines)
        return sender.isEmpty ? "Unknown sender" : sender
    }

    private static func titleWithSpamPrefix(_ title: String) -> String {
        guard !hasSpamPrefix(title) else { return title }
        return "\(spamTitlePrefix) \(title)"
    }

    private static func hasSpamPrefix(_ title: String) -> Bool {
        let normalized = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.hasPrefix("(spam)") || normalized.hasPrefix("[spam]")
    }

    static func timeText(
        for header: MessageHeader,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let rawDate = header.date.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawDate.isEmpty else { return "Time unknown" }
        guard let date = parseMailDate(rawDate) else { return rawDate }
        return sentDateText(
            for: date,
            relativeTo: now,
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        )
    }

    private static func parseMailDate(_ rawDate: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for candidate in [rawDate, rawDate.removingTrailingParenthesizedTimeZoneComment()] {
            for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z"] {
                formatter.dateFormat = format
                if let date = formatter.date(from: candidate) {
                    return date
                }
            }
        }
        return nil
    }

    private static func sentDateText(
        for date: Date,
        relativeTo now: Date,
        locale: Locale,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> String {
        let relativeDate = relativeDateText(
            for: date,
            relativeTo: now,
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        )
        let fullDateTime = fullDateTimeText(for: date, locale: locale, calendar: calendar, timeZone: timeZone)
        return "\(relativeDate), \(fullDateTime)"
    }

    private static func relativeDateText(
        for date: Date,
        relativeTo now: Date,
        locale: Locale,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone
        let components = relativeDateComponents(
            date: date,
            relativeTo: now,
            calendar: calendar
        )

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = components.month != nil || components.year != nil ? .numeric : .named
        return formatter.localizedString(from: components)
            .uppercasingFirstCharacter(locale: locale)
    }

    private static func relativeDateComponents(
        date: Date,
        relativeTo now: Date,
        calendar: Calendar
    ) -> DateComponents {
        let startOfNow = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let calendarComponents = calendar.dateComponents(
            [.year, .month, .weekOfYear, .day],
            from: startOfNow,
            to: startOfDate
        )

        if let year = calendarComponents.year, year != 0 {
            return DateComponents(year: year)
        }
        if let month = calendarComponents.month, month != 0 {
            return DateComponents(month: month)
        }
        if let week = calendarComponents.weekOfYear, week != 0 {
            return DateComponents(weekOfMonth: week)
        }
        return DateComponents(day: calendarComponents.day ?? 0)
    }

    private static func fullDateTimeText(
        for date: Date,
        locale: Locale,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var looksLikeEmailAddress: Bool {
        contains("@") && !contains(" ")
    }

    func uppercasingFirstCharacter(locale: Locale) -> String {
        guard let first else { return self }
        return String(first).uppercased(with: locale) + dropFirst()
    }

    func removingTrailingParenthesizedTimeZoneComment() -> String {
        replacing(
            #/\s+\([A-Za-z_/\-+0-9: ]+\)\s*$/#,
            with: ""
        )
    }
}
