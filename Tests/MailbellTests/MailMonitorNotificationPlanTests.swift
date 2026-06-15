@testable import mailbell
import XCTest

final class MailMonitorNotificationPlanTests: XCTestCase {
    func testFirstReconnectBatchFetchesOnlyNewestUIDsAndAdvancesCheckpoint() {
        let uids = Array(101 ... 125)

        let plan = MailMonitor.notificationPlan(uids: uids, lastSeenUID: 100, limit: 10)

        XCTAssertEqual(plan.uidsToFetch, Array(116 ... 125))
        XCTAssertEqual(plan.lastSeenUID, 125)
    }

    func testNotificationPlanIgnoresAlreadySeenUIDs() {
        let plan = MailMonitor.notificationPlan(uids: [8, 10], lastSeenUID: 10, limit: 10)

        XCTAssertTrue(plan.uidsToFetch.isEmpty)
        XCTAssertEqual(plan.lastSeenUID, 10)
    }

    func testNotificationPlanDeduplicatesUIDsBeforeCapping() {
        let plan = MailMonitor.notificationPlan(uids: [11, 12, 12, 13, 14], lastSeenUID: 10, limit: 3)

        XCTAssertEqual(plan.uidsToFetch, [12, 13, 14])
        XCTAssertEqual(plan.lastSeenUID, 14)
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

        let plan = MailMonitor.notificationPlan(uids: [11], lastSeenUID: checkpoint.lastSeenUID)

        XCTAssertEqual(plan.uidsToFetch, [11])
        XCTAssertEqual(plan.lastSeenUID, 11)
    }

    func testSpamMailboxDiscoveryFallsBackToInboxOnly() {
        XCTAssertEqual(
            MailMonitor.monitoredMailboxes(includeSpam: true, spamMailboxName: nil),
            [MonitoredMailbox(role: .inbox, name: "INBOX")]
        )
        XCTAssertEqual(
            MailMonitor.monitoredMailboxes(includeSpam: true, spamMailboxName: "  "),
            [MonitoredMailbox(role: .inbox, name: "INBOX")]
        )
    }

    func testSpamMailboxDiscoveryIncludesSpamWhenAvailable() {
        XCTAssertEqual(
            MailMonitor.monitoredMailboxes(includeSpam: true, spamMailboxName: "[Gmail]/Spam"),
            [
                MonitoredMailbox(role: .inbox, name: "INBOX"),
                MonitoredMailbox(role: .spam, name: "[Gmail]/Spam")
            ]
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "mailbell.MailMonitorNotificationPlanTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
