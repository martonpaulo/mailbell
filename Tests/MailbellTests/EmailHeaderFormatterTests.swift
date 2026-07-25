@testable import mailbell
import XCTest

final class EmailHeaderFormatterTests: XCTestCase {
    func testSenderIdentitySeparatesDisplayNameAndAddress() {
        let sender = EmailHeaderFormatter.senderIdentity(
            from: "\"Contabilizei Contabilidade Online\" <mensalidade@contabilizei.com.br>"
        )

        XCTAssertEqual(sender.name, "Contabilizei Contabilidade Online")
        XCTAssertEqual(sender.address, "mensalidade@contabilizei.com.br")
    }

    func testSenderIdentityKeepsPlainSenderWithoutDuplicateAddress() {
        let sender = EmailHeaderFormatter.senderIdentity(from: "Newsletter")

        XCTAssertEqual(sender.name, "Newsletter")
        XCTAssertNil(sender.address)
    }

    func testTimeTextIncludesRelativeDateFullDateAndTime() {
        let text = EmailHeaderFormatter.timeText(
            for: MessageHeader(
                uid: 1,
                from: "Sender <sender@example.com>",
                subject: "Subject",
                date: "Sun, 14 Jun 2026 09:30:00 +0000",
                gmThreadId: nil
            ),
            now: Date(timeIntervalSince1970: 1_781_432_400),
            locale: Locale(identifier: "en_US"),
            calendar: utcGregorianCalendar,
            timeZone: utcTimeZone
        )

        XCTAssertTrue(text.hasPrefix("Today, "), text)
        XCTAssertTrue(text.contains("Jun 14, 2026"), text)
        XCTAssertTrue(text.contains("9:30"), text)
    }

    func testTimeTextUsesRelativeDistanceForOlderDates() {
        let text = EmailHeaderFormatter.timeText(
            for: MessageHeader(
                uid: 1,
                from: "Sender <sender@example.com>",
                subject: "Subject",
                date: "Thu, 11 Jun 2026 09:30:00 +0000",
                gmThreadId: nil
            ),
            now: Date(timeIntervalSince1970: 1_781_432_400),
            locale: Locale(identifier: "en_US"),
            calendar: utcGregorianCalendar,
            timeZone: utcTimeZone
        )

        XCTAssertTrue(text.hasPrefix("3 days ago, "), text)
        XCTAssertTrue(text.contains("Jun 11, 2026"), text)
        XCTAssertTrue(text.contains("9:30"), text)
    }

    func testTimeTextUsesYesterdayForPreviousCalendarDay() {
        let text = EmailHeaderFormatter.timeText(
            for: MessageHeader(
                uid: 1,
                from: "Sender <sender@example.com>",
                subject: "Subject",
                date: "Thu, 25 Jun 2026 09:30:00 +0000",
                gmThreadId: nil
            ),
            now: date(year: 2026, month: 6, day: 26, hour: 9, minute: 30),
            locale: Locale(identifier: "en_US"),
            calendar: utcGregorianCalendar,
            timeZone: utcTimeZone
        )

        XCTAssertTrue(text.hasPrefix("Yesterday, "), text)
        XCTAssertTrue(text.contains("Jun 25, 2026"), text)
    }

    func testTimeTextUsesWeeksForDatesBelowOneCalendarMonth() {
        let text = EmailHeaderFormatter.timeText(
            for: MessageHeader(
                uid: 1,
                from: "Sender <sender@example.com>",
                subject: "Subject",
                date: "Wed, 27 May 2026 09:30:00 +0000",
                gmThreadId: nil
            ),
            now: date(year: 2026, month: 6, day: 26, hour: 9, minute: 30),
            locale: Locale(identifier: "en_US"),
            calendar: utcGregorianCalendar,
            timeZone: utcTimeZone
        )

        XCTAssertTrue(text.hasPrefix("4 weeks ago, "), text)
        XCTAssertTrue(text.contains("May 27, 2026"), text)
    }

    func testTimeTextUsesMonthsForCalendarMonthDifference() {
        let text = EmailHeaderFormatter.timeText(
            for: MessageHeader(
                uid: 1,
                from: "Sender <sender@example.com>",
                subject: "Subject",
                date: "Tue, 26 May 2026 09:30:00 +0000",
                gmThreadId: nil
            ),
            now: date(year: 2026, month: 6, day: 26, hour: 9, minute: 30),
            locale: Locale(identifier: "en_US"),
            calendar: utcGregorianCalendar,
            timeZone: utcTimeZone
        )

        XCTAssertTrue(text.hasPrefix("1 month ago, "), text)
        XCTAssertTrue(text.contains("May 26, 2026"), text)
    }

    func testTimeTextUsesPluralMonthsBeforeFullYear() {
        let text = EmailHeaderFormatter.timeText(
            for: MessageHeader(
                uid: 1,
                from: "Sender <sender@example.com>",
                subject: "Subject",
                date: "Tue, 26 Aug 2025 09:30:00 +0000",
                gmThreadId: nil
            ),
            now: date(year: 2026, month: 6, day: 26, hour: 9, minute: 30),
            locale: Locale(identifier: "en_US"),
            calendar: utcGregorianCalendar,
            timeZone: utcTimeZone
        )

        XCTAssertTrue(text.hasPrefix("10 months ago, "), text)
        XCTAssertTrue(text.contains("Aug 26, 2025"), text)
    }

    func testTimeTextUsesYearAcrossLeapDayCalendarDifference() {
        let text = EmailHeaderFormatter.timeText(
            for: MessageHeader(
                uid: 1,
                from: "Sender <sender@example.com>",
                subject: "Subject",
                date: "Thu, 29 Feb 2024 09:30:00 +0000",
                gmThreadId: nil
            ),
            now: date(year: 2025, month: 3, day: 1, hour: 9, minute: 30),
            locale: Locale(identifier: "en_US"),
            calendar: utcGregorianCalendar,
            timeZone: utcTimeZone
        )

        XCTAssertTrue(text.hasPrefix("1 year ago, "), text)
        XCTAssertTrue(text.contains("Feb 29, 2024"), text)
    }

    func testTimeTextUsesYearsForDatesMoreThanOneYearAgo() {
        let text = EmailHeaderFormatter.timeText(
            for: MessageHeader(
                uid: 1,
                from: "Sender <sender@example.com>",
                subject: "Subject",
                date: "Wed, 26 Jun 2024 09:30:00 +0000",
                gmThreadId: nil
            ),
            now: date(year: 2026, month: 6, day: 26, hour: 9, minute: 30),
            locale: Locale(identifier: "en_US"),
            calendar: utcGregorianCalendar,
            timeZone: utcTimeZone
        )

        XCTAssertTrue(text.hasPrefix("2 years ago, "), text)
        XCTAssertTrue(text.contains("Jun 26, 2024"), text)
    }

    func testTimeTextConvertsUTCHeaderCommentToLocalTime() throws {
        let localTimeZone = TimeZone(secondsFromGMT: -3 * 60 * 60)!
        let calendar = gregorianCalendar(timeZone: localTimeZone)
        let now = try XCTUnwrap(DateComponents(
            calendar: calendar,
            timeZone: localTimeZone,
            year: 2026,
            month: 6,
            day: 26,
            hour: 10,
            minute: 30
        ).date)
        let text = EmailHeaderFormatter.timeText(
            for: MessageHeader(
                uid: 1,
                from: "Sender <sender@example.com>",
                subject: "Subject",
                date: "Fri, 26 Jun 2026 13:29:33 +0000 (UTC)",
                gmThreadId: nil
            ),
            now: now,
            locale: Locale(identifier: "en_US"),
            calendar: calendar,
            timeZone: localTimeZone
        )

        XCTAssertTrue(text.hasPrefix("Today, "), text)
        XCTAssertTrue(text.contains("Jun 26, 2026"), text)
        XCTAssertTrue(text.contains("10:29"), text)
        XCTAssertFalse(text.contains("+0000"), text)
        XCTAssertFalse(text.contains("UTC"), text)
    }

    private var utcGregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utcTimeZone
        return calendar
    }

    private static let utcTimeZone = TimeZone(secondsFromGMT: 0)!

    private var utcTimeZone: TimeZone {
        Self.utcTimeZone
    }

    private func gregorianCalendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        DateComponents(
            calendar: utcGregorianCalendar,
            timeZone: utcTimeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }
}
