@testable import mailbell
import XCTest

final class MailMonitorNotificationPlanTests: XCTestCase {
    func testFetchPlanAdmitsAllFreshUIDsAndCapsNotificationsToNewestUIDs() {
        let uids = Array(101 ... 180)

        let plan = MailMonitor.notificationPlan(
            uids: uids,
            lastSeenUID: 100,
            notificationLimit: 10
        )

        XCTAssertEqual(plan.uidsToAdmit, Array(101 ... 180))
        XCTAssertEqual(plan.admissionBatches, [Array(101 ... 180)])
        XCTAssertEqual(plan.uidsToNotify, Array(171 ... 180))
        XCTAssertEqual(plan.lastSeenUID, 180)
    }

    func testFetchPlanChunksLargeBurstsWithoutChangingNotificationCap() {
        let uids = Array(101 ... 260)

        let plan = MailMonitor.notificationPlan(
            uids: uids,
            lastSeenUID: 100,
            notificationLimit: 10,
            admissionBatchSize: 50
        )

        XCTAssertEqual(plan.admissionBatches, [
            Array(101 ... 150),
            Array(151 ... 200),
            Array(201 ... 250),
            Array(251 ... 260)
        ])
        XCTAssertEqual(plan.uidsToAdmit, uids)
        XCTAssertEqual(plan.uidsToNotify, Array(251 ... 260))
        XCTAssertEqual(plan.lastSeenUID, 260)
    }

    func testFetchPlanDoesNotAdvanceCheckpointWithoutAdmissionBatches() {
        let plan = MailMonitor.notificationPlan(
            uids: [101, 102],
            lastSeenUID: 100,
            notificationLimit: 10,
            admissionBatchSize: 0
        )

        XCTAssertTrue(plan.admissionBatches.isEmpty)
        XCTAssertTrue(plan.uidsToAdmit.isEmpty)
        XCTAssertEqual(plan.uidsToNotify, [101, 102])
        XCTAssertEqual(plan.lastSeenUID, 100)
    }

    func testNotificationPlanIgnoresAlreadySeenUIDs() {
        let plan = MailMonitor.notificationPlan(uids: [8, 10], lastSeenUID: 10, notificationLimit: 10)

        XCTAssertTrue(plan.uidsToAdmit.isEmpty)
        XCTAssertTrue(plan.uidsToNotify.isEmpty)
        XCTAssertEqual(plan.lastSeenUID, 10)
    }

    func testNotificationPlanDeduplicatesUIDsBeforeCapping() {
        let plan = MailMonitor.notificationPlan(
            uids: [11, 12, 12, 13, 14],
            lastSeenUID: 10,
            notificationLimit: 3
        )

        XCTAssertEqual(plan.uidsToAdmit, [11, 12, 13, 14])
        XCTAssertEqual(plan.uidsToNotify, [12, 13, 14])
        XCTAssertEqual(plan.lastSeenUID, 14)
    }

    func testNotificationPlanCanAdmitPendingWithoutPostingNotifications() {
        let plan = MailMonitor.notificationPlan(uids: [11, 12], lastSeenUID: 10, notificationLimit: 0)

        XCTAssertEqual(plan.uidsToAdmit, [11, 12])
        XCTAssertTrue(plan.uidsToNotify.isEmpty)
        XCTAssertEqual(plan.lastSeenUID, 12)
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

        XCTAssertEqual(plan.uidsToAdmit, [11])
        XCTAssertEqual(plan.uidsToNotify, [11])
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
