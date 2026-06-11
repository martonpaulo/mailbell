@testable import mailbell
import XCTest

final class TokenStoreTests: XCTestCase {
    func testSavePersistsSingleSessionItem() throws {
        let accountID = UUID()
        let fixture = KeychainFixture()
        let store = TokenStore(accountID: accountID, keychain: fixture.client)
        let tokens = GoogleTokens(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1234)
        )

        try store.save(tokens: tokens)

        XCTAssertEqual(fixture.values.count, 1)
        let session = try XCTUnwrap(fixture.values[Self.sessionAccount(accountID)])
        let decoded = try JSONDecoder().decode(GoogleTokens.self, from: Data(session.utf8))
        XCTAssertEqual(decoded.accessToken, "access-token")
        XCTAssertEqual(decoded.refreshToken, "refresh-token")
        XCTAssertEqual(decoded.expiresAt, Date(timeIntervalSince1970: 1234))
    }

    func testSavePropagatesKeychainWriteFailure() {
        let fixture = KeychainFixture(setError: Keychain.KeychainError.unexpectedStatus(errSecAuthFailed))
        let store = TokenStore(accountID: UUID(), keychain: fixture.client)
        let tokens = GoogleTokens(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1234)
        )

        XCTAssertThrowsError(try store.save(tokens: tokens)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                Keychain.KeychainError.unexpectedStatus(errSecAuthFailed).localizedDescription
            )
        }
        XCTAssertTrue(fixture.values.isEmpty)
    }

    func testSaveRestoresPreviousSessionWhenSessionWriteFails() {
        let accountID = UUID()
        let sessionAccount = Self.sessionAccount(accountID)
        let fixture = KeychainFixture(
            setError: Keychain.KeychainError.unexpectedStatus(errSecAuthFailed),
            failingAccounts: [sessionAccount]
        )
        fixture.values[sessionAccount] = "previous-session"
        let store = TokenStore(accountID: accountID, keychain: fixture.client)
        let tokens = GoogleTokens(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            expiresAt: Date(timeIntervalSince1970: 1234)
        )

        XCTAssertThrowsError(try store.save(tokens: tokens))

        XCTAssertEqual(fixture.values[sessionAccount], "previous-session")
    }

    func testClearRemovesSessionItem() {
        let accountID = UUID()
        let fixture = KeychainFixture()
        fixture.values[Self.sessionAccount(accountID)] = "session"

        TokenStore(accountID: accountID, keychain: fixture.client).clear()

        XCTAssertNil(fixture.values[Self.sessionAccount(accountID)])
        XCTAssertEqual(fixture.deletedAccounts, [Self.sessionAccount(accountID)])
    }

    private static func sessionAccount(_ accountID: UUID) -> String {
        "mailbell.account.\(accountID.uuidString).gmail.session"
    }
}

private final class KeychainFixture: @unchecked Sendable {
    var values: [String: String] = [:]
    var deletedAccounts: [String] = []

    private let setError: Error?
    private let failsAllAccounts: Bool
    private var failingAccounts: Set<String>

    init(setError: Error? = nil, failingAccounts: Set<String> = []) {
        self.setError = setError
        failsAllAccounts = setError != nil && failingAccounts.isEmpty
        self.failingAccounts = failingAccounts
    }

    var client: KeychainClient {
        KeychainClient(
            set: { [self] value, account in
                if let setError {
                    if failsAllAccounts {
                        throw setError
                    }
                    if failingAccounts.contains(account) {
                        failingAccounts.remove(account)
                        throw setError
                    }
                }
                values[account] = value
            },
            get: { [self] account in
                values[account]
            },
            delete: { [self] account in
                deletedAccounts.append(account)
                values.removeValue(forKey: account)
            }
        )
    }
}
