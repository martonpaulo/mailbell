@testable import mailbell
import XCTest

final class AccountStoreTests: XCTestCase {
    func testLoadsSavedAccounts() {
        let defaults = makeDefaults()
        let store = AccountStore(userDefaults: defaults)
        let createdAt = Date(timeIntervalSince1970: 1)
        let account = MailAccount(providerID: .gmail, email: "first@example.com", createdAt: createdAt)

        store.saveAccounts([account])

        XCTAssertEqual(store.loadAccounts(), [account])
    }

    func testUpsertReplacesByID() {
        let defaults = makeDefaults()
        let store = AccountStore(userDefaults: defaults)
        let account = MailAccount(providerID: .gmail, email: "old@example.com")
        let updated = MailAccount(id: account.id, providerID: .gmail, email: "new@example.com")

        _ = store.upsert(account)
        let accounts = store.upsert(updated)

        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.email, "new@example.com")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "mailbell.AccountStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
