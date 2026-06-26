@testable import mailbell
import XCTest

final class EmailHeaderFormatterTests: XCTestCase {
    func testTitlePrefixesSpamMailbox() {
        let title = EmailHeaderFormatter.title(
            for: MessageHeader(
                uid: 1,
                mailbox: .spam,
                from: "Sender <sender@example.com>",
                subject: "Limited time offer",
                date: "",
                gmThreadId: nil
            )
        )

        XCTAssertEqual(title, "(SPAM) Limited time offer")
    }

    func testTitleDoesNotDuplicateExistingSpamMarker() {
        let title = EmailHeaderFormatter.title(
            for: MessageHeader(
                uid: 1,
                mailbox: .spam,
                from: "Sender <sender@example.com>",
                subject: "[SPAM] Limited time offer",
                date: "",
                gmThreadId: nil
            )
        )

        XCTAssertEqual(title, "[SPAM] Limited time offer")
    }

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

    func testTimeTextConvertsUTCHeaderCommentToLocalTime() {
        let localTimeZone = TimeZone(secondsFromGMT: -3 * 60 * 60)!
        let calendar = gregorianCalendar(timeZone: localTimeZone)
        let now = DateComponents(
            calendar: calendar,
            timeZone: localTimeZone,
            year: 2026,
            month: 6,
            day: 26,
            hour: 10,
            minute: 30
        ).date!
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
}
