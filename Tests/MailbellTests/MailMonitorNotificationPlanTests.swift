@testable import mailbell
import XCTest

final class MailMonitorNotificationPlanTests: XCTestCase {
    func testFirstReconnectBatchNotifiesOnlyNewestHeadersAndAdvancesCheckpoint() {
        let headers = (101...125).map { uid in
            MessageHeader(uid: uid, from: "sender@example.com", subject: "Subject \(uid)", date: "", gmThreadId: nil)
        }

        let plan = MailMonitor.notificationPlan(headers: headers, lastSeenUID: 100, limit: 10)

        XCTAssertEqual(plan.headersToNotify.map(\.uid), Array(116...125))
        XCTAssertEqual(plan.lastSeenUID, 125)
    }

    func testNotificationPlanIgnoresAlreadySeenHeaders() {
        let headers = [
            MessageHeader(uid: 8, from: "old@example.com", subject: "Old", date: "", gmThreadId: nil),
            MessageHeader(uid: 10, from: "seen@example.com", subject: "Seen", date: "", gmThreadId: nil)
        ]

        let plan = MailMonitor.notificationPlan(headers: headers, lastSeenUID: 10, limit: 10)

        XCTAssertTrue(plan.headersToNotify.isEmpty)
        XCTAssertEqual(plan.lastSeenUID, 10)
    }
}
