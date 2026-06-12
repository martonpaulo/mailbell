@testable import mailbell
import XCTest

final class EmailStoreTests: XCTestCase {
    @MainActor
    func testAdmitsUnreadEmailWhenNotHandled() {
        let store = makeStore()
        let account = makeAccount()
        let header = makeHeader(gmMessageId: "1001")

        XCTAssertTrue(store.admit(header: header, account: account))

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.title, "Subject")
        XCTAssertEqual(store.items.first?.sender, "Sender <sender@example.com>")
    }

    @MainActor
    func testDismissedEmailIsExcludedAfterRelaunch() {
        let defaults = makeDefaults()
        let account = makeAccount()
        let header = makeHeader(gmMessageId: "1002")
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)

        let store = makeStore(defaults: defaults)
        XCTAssertTrue(store.admit(header: header, account: account))
        store.dismiss(id: id)

        let relaunchedStore = makeStore(defaults: defaults)
        XCTAssertFalse(relaunchedStore.admit(header: header, account: account))
        XCTAssertTrue(relaunchedStore.items.isEmpty)
    }

    @MainActor
    func testOpenedEmailIsExcludedAfterRelaunch() {
        let defaults = makeDefaults()
        let account = makeAccount()
        let header = makeHeader(gmMessageId: "1003")
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)

        let store = makeStore(defaults: defaults)
        XCTAssertTrue(store.admit(header: header, account: account))
        store.markOpened(id: id)

        let relaunchedStore = makeStore(defaults: defaults)
        XCTAssertFalse(relaunchedStore.admit(header: header, account: account))
        XCTAssertTrue(relaunchedStore.items.isEmpty)
    }

    @MainActor
    func testDuplicateEmailsAreDeduplicatedByStableID() {
        let store = makeStore()
        let account = makeAccount()

        let firstHeader = makeHeader(uid: 1, subject: "First", gmMessageId: "same")
        let duplicateHeader = makeHeader(uid: 2, subject: "Second", gmMessageId: "same")

        XCTAssertTrue(store.admit(header: firstHeader, account: account))
        XCTAssertFalse(store.admit(header: duplicateHeader, account: account))

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.title, "First")
    }

    func testStableIdentityPrefersProviderIDsOverSubject() {
        let account = makeAccount()
        let first = makeHeader(uid: 1, subject: "First", gmMessageId: "provider-id")
        let second = makeHeader(uid: 2, subject: "Second", gmMessageId: "provider-id")

        XCTAssertEqual(
            EmailStoreIdentity.id(accountID: account.id, header: first),
            EmailStoreIdentity.id(accountID: account.id, header: second)
        )
    }

    @MainActor
    func testDismissAndOpenAreIdempotent() {
        let defaults = makeDefaults()
        let account = makeAccount()
        let header = makeHeader(gmMessageId: "1004")
        let id = EmailStoreIdentity.id(accountID: account.id, header: header)
        let store = makeStore(defaults: defaults)

        XCTAssertTrue(store.admit(header: header, account: account))
        store.dismiss(id: id)
        store.dismiss(id: id)
        store.markOpened(id: id)
        store.markOpened(id: id)

        XCTAssertTrue(store.items.isEmpty)

        let relaunchedStore = makeStore(defaults: defaults)
        XCTAssertFalse(relaunchedStore.admit(header: header, account: account))
    }

    func testHandledPersistencePrunesToBoundedRecentSet() {
        let defaults = makeDefaults()
        var timestamp = Date(timeIntervalSince1970: 1)
        let persistence = EmailStorePersistence(
            userDefaults: defaults,
            maxRecordCount: 2,
            now: { timestamp }
        )

        persistence.mark("old", disposition: .dismissed)
        timestamp = Date(timeIntervalSince1970: 2)
        persistence.mark("middle", disposition: .dismissed)
        timestamp = Date(timeIntervalSince1970: 3)
        persistence.mark("new", disposition: .opened)

        XCTAssertFalse(persistence.isHandled("old"))
        XCTAssertTrue(persistence.isHandled("middle"))
        XCTAssertTrue(persistence.isHandled("new"))
    }

    @MainActor
    private func makeStore(defaults: UserDefaults? = nil) -> EmailStore {
        let persistence = EmailStorePersistence(userDefaults: defaults ?? makeDefaults())
        return EmailStore(
            persistence: persistence,
            now: { Date(timeIntervalSince1970: 1_806_000_000) }
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "mailbell.EmailStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeAccount() -> MailAccount {
        MailAccount(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            providerID: .gmail,
            email: "account@example.com"
        )
    }

    private func makeHeader(
        uid: Int = 1,
        subject: String = "Subject",
        gmMessageId: String? = nil,
        gmThreadId: String? = nil,
        messageId: String? = nil
    ) -> MessageHeader {
        MessageHeader(
            uid: uid,
            from: "Sender <sender@example.com>",
            subject: subject,
            date: "Tue, 02 Jun 2026 12:00:00 +0000",
            gmThreadId: gmThreadId,
            gmMessageId: gmMessageId,
            messageId: messageId
        )
    }
}
