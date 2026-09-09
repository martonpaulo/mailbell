@testable import mailbell
import XCTest

/// Handled history: what survives a relaunch, what gets pruned, and what
/// happens when the saved payload cannot be read or written.
final class EmailStorePersistenceTests: XCTestCase {
    func testHandledPersistencePrunesToBoundedRecentSet() throws {
        let defaults = EmailStoreFixture.makeDefaults()
        var timestamp = Date(timeIntervalSince1970: 1)
        let persistence = EmailStorePersistence(
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
        let defaults = EmailStoreFixture.makeDefaults()
        let firstPersistence = EmailStorePersistence(userDefaults: defaults)

        try firstPersistence.mark(HandledMessage(id: "persisted", identity: nil), disposition: .opened)

        let secondPersistence = EmailStorePersistence(userDefaults: defaults)
        XCTAssertTrue(try secondPersistence.isHandled("persisted"))
    }

    func testCorruptHandledPersistenceIsBackedUpOnceAndRecoveredWithWarning() throws {
        let defaults = EmailStoreFixture.makeDefaults()
        let corrupt = Data("not-json".utf8)
        defaults.set(corrupt, forKey: EmailStorePersistence.recordsKey)
        let persistence = EmailStorePersistence(userDefaults: defaults)

        XCTAssertFalse(try persistence.isHandled("anything"))

        XCTAssertEqual(defaults.data(forKey: EmailStorePersistence.corruptBackupKey), corrupt)
        let activeData = try XCTUnwrap(defaults.data(forKey: EmailStorePersistence.recordsKey))
        let decoded = try JSONDecoder().decode([String: String].self, from: activeData)
        XCTAssertTrue(decoded.isEmpty)
        XCTAssertEqual(persistence.takeRecoveryWarning(), EmailStorePersistence.recoveryWarning)
        XCTAssertNil(persistence.takeRecoveryWarning())

        let reloadedPersistence = EmailStorePersistence(userDefaults: defaults)
        XCTAssertFalse(try reloadedPersistence.isHandled("anything"))
        XCTAssertNil(reloadedPersistence.takeRecoveryWarning())
    }

    func testCorruptHandledPersistenceBackupFailurePreservesOriginalPayload() {
        let defaults = EmailStoreFixture.makeDefaults()
        let corrupt = Data("not-json".utf8)
        defaults.set(corrupt, forKey: EmailStorePersistence.recordsKey)
        let persistence = EmailStorePersistence(
            userDefaults: defaults,
            saveData: { _, key in
                if key == EmailStorePersistence.corruptBackupKey {
                    throw EmailStorePersistence.PersistenceError.saveFailed("disk full")
                }
            }
        )

        XCTAssertThrowsError(try persistence.isHandled("anything")) { error in
            XCTAssertEqual(error.localizedDescription, "Could not save handled-message history: disk full")
        }
        XCTAssertEqual(defaults.data(forKey: EmailStorePersistence.recordsKey), corrupt)
        XCTAssertNil(defaults.data(forKey: EmailStorePersistence.corruptBackupKey))
        XCTAssertNil(persistence.takeRecoveryWarning())
    }

    @MainActor
    func testDismissSaveFailureLeavesDurableCacheAndVisiblePendingStateUnchanged() throws {
        let defaults = EmailStoreFixture.makeDefaults()
        var shouldFail = false
        let persistence = EmailStorePersistence(
            userDefaults: defaults,
            saveData: { data, key in
                if shouldFail {
                    throw EmailStorePersistence.PersistenceError.saveFailed("disk full")
                }
                defaults.set(data, forKey: key)
            }
        )
        let store = EmailStore(persistence: persistence)
        let account = EmailStoreFixture.makeAccount()
        let header = EmailStoreFixture.makeHeader(gmMessageId: "atomic-dismiss")
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)

        XCTAssertTrue(try store.admit(header: header, account: account))
        shouldFail = true

        XCTAssertThrowsError(try store.dismiss(id: id)) { error in
            XCTAssertEqual(error.localizedDescription, "Could not save handled-message history: disk full")
        }
        XCTAssertEqual(store.items.map(\.id), [id])
        let relaunchedStore = EmailStoreFixture.makeStore(defaults: defaults)
        XCTAssertTrue(try relaunchedStore.admit(header: header, account: account))
    }

    @MainActor
    func testAccountRecordRemovalFailureLeavesVisibleItemsUntouched() throws {
        let defaults = EmailStoreFixture.makeDefaults()
        var shouldFail = false
        let persistence = EmailStorePersistence(
            userDefaults: defaults,
            saveData: { data, key in
                if shouldFail {
                    throw EmailStorePersistence.PersistenceError.saveFailed("disk full")
                }
                defaults.set(data, forKey: key)
            }
        )
        let store = EmailStore(persistence: persistence)
        let account = EmailStoreFixture.makeAccount()
        let handledHeader = EmailStoreFixture.makeHeader(gmMessageId: "account-removal-handled")
        let visibleHeader = EmailStoreFixture.makeHeader(uid: 2, gmMessageId: "account-removal-visible")

        XCTAssertTrue(try store.admit(header: handledHeader, account: account))
        try store.dismiss(id: EmailStoreIdentity.id(accountID: account.id, header: handledHeader))
        XCTAssertFalse(try store.admit(header: handledHeader, account: account))
        XCTAssertTrue(try store.admit(header: visibleHeader, account: account))
        let visibleID = EmailStoreIdentity.id(accountID: account.id, header: visibleHeader)
        shouldFail = true

        XCTAssertThrowsError(try store.removeAccountRecords(accountID: account.id)) { error in
            XCTAssertEqual(error.localizedDescription, "Could not save handled-message history: disk full")
        }
        XCTAssertEqual(store.items.map(\.id), [visibleID])
        let relaunchedStore = EmailStoreFixture.makeStore(defaults: defaults)
        XCTAssertFalse(try relaunchedStore.admit(header: handledHeader, account: account))
    }
}
