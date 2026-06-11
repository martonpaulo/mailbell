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

    func testTestNotificationDoesNotMutateCheckpointOrBlockLaterRealNotification() {
        let defaults = makeDefaults()
        let account = MailAccount(providerID: .gmail, email: "account@example.com")
        var checkpoint = CheckpointStore(accountID: account.id, userDefaults: defaults)
        checkpoint.storedUIDValidity = 99
        checkpoint.lastSeenUID = 10

        _ = NotificationManager.testNotificationContent(account: account)

        XCTAssertEqual(checkpoint.storedUIDValidity, 99)
        XCTAssertEqual(checkpoint.lastSeenUID, 10)

        let realHeader = MessageHeader(
            uid: 11,
            from: "Ana Silva <ana@example.com>",
            subject: "Real message",
            date: "",
            gmThreadId: nil
        )
        let plan = MailMonitor.notificationPlan(headers: [realHeader], lastSeenUID: checkpoint.lastSeenUID)

        XCTAssertEqual(plan.headersToNotify, [realHeader])
        XCTAssertEqual(plan.lastSeenUID, 11)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "mailbell.MailMonitorNotificationPlanTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
