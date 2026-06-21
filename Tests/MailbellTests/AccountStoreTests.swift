@testable import mailbell
import XCTest

final class AccountStoreTests: XCTestCase {
    func testLoadsSavedAccounts() throws {
        let defaults = makeDefaults()
        let store = AccountStore(userDefaults: defaults)
        let createdAt = Date(timeIntervalSince1970: 1)
        let account = MailAccount(providerID: .gmail, email: "first@example.com", createdAt: createdAt)

        try store.saveAccounts([account])

        XCTAssertEqual(try store.loadAccounts(), [account])
    }

    func testUpsertReplacesByID() throws {
        let defaults = makeDefaults()
        let store = AccountStore(userDefaults: defaults)
        let account = MailAccount(providerID: .gmail, email: "old@example.com")
        let updated = MailAccount(id: account.id, providerID: .gmail, email: "new@example.com")

        _ = try store.upsert(account)
        let accounts = try store.upsert(updated)

        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.email, "new@example.com")
    }

    func testSaveFailureIsPropagated() {
        let store = AccountStore(
            userDefaults: makeDefaults(),
            saveData: { _, _ in throw AccountStore.AccountStoreError.saveFailed("disk full") }
        )
        let account = MailAccount(providerID: .gmail, email: "first@example.com")

        XCTAssertThrowsError(try store.saveAccounts([account])) { error in
            XCTAssertEqual(error.localizedDescription, "Could not save accounts: disk full")
        }
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "mailbell.AccountStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
