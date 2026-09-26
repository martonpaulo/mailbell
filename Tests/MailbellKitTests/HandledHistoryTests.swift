import XCTest

@testable import MailbellKit

/// Handled history: what survives a relaunch, what gets pruned, and what
/// happens when the saved payload cannot be read or written.
@MainActor
final class HandledHistoryTests: XCTestCase {
    func testHandledPersistencePrunesToBoundedRecentSet() throws {
        let defaults = ReviewQueueFixture.makeDefaults()
        var timestamp = Date(timeIntervalSince1970: 1)
        let persistence = HandledHistory(
            userDefaults: defaults,
            maxRecordCount: 2,
            now: { timestamp }
        )

        try persistence.mark(HandledMessage(id: "old", identity: nil), disposition: .dismissed)
        timestamp = Date(timeIntervalSince1970: 2)
        try persistence.mark(HandledMessage(id: "middle", identity: nil), disposition: .dismissed)
        timestamp = Date(timeIntervalSince1970: 3)
        try persistence.mark(HandledMessage(id: "new", identity: nil), disposition: .opened)

        XCTAssertFalse(try persistence.isHandled("old"))
        XCTAssertTrue(try persistence.isHandled("middle"))
        XCTAssertTrue(try persistence.isHandled("new"))
    }

    func testHandledPersistenceLoadsRecordsAcrossInstances() throws {
        let defaults = ReviewQueueFixture.makeDefaults()
        let firstPersistence = HandledHistory(userDefaults: defaults)

        try firstPersistence.mark(HandledMessage(id: "persisted", identity: nil), disposition: .opened)

        let secondPersistence = HandledHistory(userDefaults: defaults)
        XCTAssertTrue(try secondPersistence.isHandled("persisted"))
    }

    func testCorruptHandledPersistenceIsBackedUpOnceAndRecoveredWithWarning() throws {
        let defaults = ReviewQueueFixture.makeDefaults()
        let corrupt = Data("not-json".utf8)
        defaults.set(corrupt, forKey: StorageKeys.handledRecords)
        let persistence = HandledHistory(userDefaults: defaults)

        XCTAssertFalse(try persistence.isHandled("anything"))

        XCTAssertEqual(defaults.data(forKey: StorageKeys.handledRecordsCorruptBackup), corrupt)
        let activeData = try XCTUnwrap(defaults.data(forKey: StorageKeys.handledRecords))
        let decoded = try JSONDecoder().decode([String: String].self, from: activeData)
        XCTAssertTrue(decoded.isEmpty)
        XCTAssertEqual(persistence.takeRecoveryWarning(), HandledHistory.recoveryWarning)
        XCTAssertNil(persistence.takeRecoveryWarning())

        let reloadedPersistence = HandledHistory(userDefaults: defaults)
        XCTAssertFalse(try reloadedPersistence.isHandled("anything"))
        XCTAssertNil(reloadedPersistence.takeRecoveryWarning())
    }

    func testCorruptHandledPersistenceBackupFailurePreservesOriginalPayload() {
        let defaults = ReviewQueueFixture.makeDefaults()
        let corrupt = Data("not-json".utf8)
        defaults.set(corrupt, forKey: StorageKeys.handledRecords)
        let persistence = HandledHistory(
            userDefaults: defaults,
            saveData: { _, key in
                if key == StorageKeys.handledRecordsCorruptBackup {
                    throw HandledHistory.PersistenceError.saveFailed("disk full")
                }
            }
        )

        XCTAssertThrowsError(try persistence.isHandled("anything")) { error in
            XCTAssertEqual(error.localizedDescription, "Couldn't save Mailbell's review history. Try again.")
        }
        XCTAssertEqual(defaults.data(forKey: StorageKeys.handledRecords), corrupt)
        XCTAssertNil(defaults.data(forKey: StorageKeys.handledRecordsCorruptBackup))
        XCTAssertNil(persistence.takeRecoveryWarning())
    }

    @MainActor
    func testDismissSaveFailureLeavesDurableCacheAndVisiblePendingStateUnchanged() throws {
        let defaults = ReviewQueueFixture.makeDefaults()
        var shouldFail = false
        let persistence = HandledHistory(
            userDefaults: defaults,
            saveData: { data, key in
                if shouldFail {
                    throw HandledHistory.PersistenceError.saveFailed("disk full")
                }
                defaults.set(data, forKey: key)
            }
        )
        let store = ReviewQueue(persistence: persistence)
        let account = ReviewQueueFixture.makeAccount()
        let header = ReviewQueueFixture.makeHeader(gmMessageId: "atomic-dismiss")
        let id = ReviewItemIdentity.id(accountID: account.id, header: header)

        XCTAssertTrue(try store.admit(header: header, account: account))
        shouldFail = true

        XCTAssertThrowsError(try store.dismiss(id: id)) { error in
            XCTAssertEqual(error.localizedDescription, "Couldn't save Mailbell's review history. Try again.")
        }
        XCTAssertEqual(store.shownItems.map(\.id), [id])
        let relaunchedStore = ReviewQueueFixture.makeStore(defaults: defaults)
        XCTAssertTrue(try relaunchedStore.admit(header: header, account: account))
    }

    @MainActor
    func testAccountRecordRemovalFailureLeavesVisibleItemsUntouched() throws {
        let defaults = ReviewQueueFixture.makeDefaults()
        var shouldFail = false
        let persistence = HandledHistory(
            userDefaults: defaults,
            saveData: { data, key in
                if shouldFail {
                    throw HandledHistory.PersistenceError.saveFailed("disk full")
                }
                defaults.set(data, forKey: key)
            }
        )
        let store = ReviewQueue(persistence: persistence)
        let account = ReviewQueueFixture.makeAccount()
        let handledHeader = ReviewQueueFixture.makeHeader(gmMessageId: "account-removal-handled")
        let visibleHeader = ReviewQueueFixture.makeHeader(uid: 2, gmMessageId: "account-removal-visible")

        XCTAssertTrue(try store.admit(header: handledHeader, account: account))
        try store.dismiss(id: ReviewItemIdentity.id(accountID: account.id, header: handledHeader))
        XCTAssertFalse(try store.admit(header: handledHeader, account: account))
        XCTAssertTrue(try store.admit(header: visibleHeader, account: account))
        let visibleID = ReviewItemIdentity.id(accountID: account.id, header: visibleHeader)
        shouldFail = true

        XCTAssertThrowsError(try store.removeAccountRecords(accountID: account.id)) { error in
            XCTAssertEqual(error.localizedDescription, "Couldn't save Mailbell's review history. Try again.")
        }
        XCTAssertEqual(store.shownItems.map(\.id), [visibleID])
        let relaunchedStore = ReviewQueueFixture.makeStore(defaults: defaults)
        XCTAssertFalse(try relaunchedStore.admit(header: handledHeader, account: account))
    }
}
