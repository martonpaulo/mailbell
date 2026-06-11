@testable import mailbell
import XCTest

final class TokenStoreTests: XCTestCase {
    func testSavePersistsRefreshAndCachedTokenMaterial() throws {
        let fixture = KeychainFixture()
        let store = TokenStore(accountID: UUID(), keychain: fixture.client)
        let tokens = GoogleTokens(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_234)
        )

        try store.save(tokens: tokens)

        let refreshEntry = try XCTUnwrap(fixture.values.first { $0.key.hasSuffix(".refreshToken") })
        XCTAssertEqual(refreshEntry.value, "refresh-token")

        let accessEntry = try XCTUnwrap(fixture.values.first { $0.key.hasSuffix(".accessToken") })
        let decoded = try JSONDecoder().decode(GoogleTokens.self, from: Data(accessEntry.value.utf8))
        XCTAssertEqual(decoded.accessToken, "access-token")
        XCTAssertEqual(decoded.refreshToken, "refresh-token")
        XCTAssertEqual(decoded.expiresAt, Date(timeIntervalSince1970: 1_234))
    }

    func testSavePropagatesKeychainWriteFailure() {
        let fixture = KeychainFixture(setError: Keychain.KeychainError.unexpectedStatus(errSecAuthFailed))
        let store = TokenStore(accountID: UUID(), keychain: fixture.client)
        let tokens = GoogleTokens(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_234)
        )

        XCTAssertThrowsError(try store.save(tokens: tokens)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                Keychain.KeychainError.unexpectedStatus(errSecAuthFailed).localizedDescription
            )
        }
        XCTAssertTrue(fixture.values.isEmpty)
    }

    func testSaveRestoresPreviousValuesWhenCachedTokenWriteFails() {
        let accountID = UUID()
        let refreshAccount = Self.refreshAccount(accountID)
        let accessAccount = Self.accessAccount(accountID)
        let fixture = KeychainFixture(
            setError: Keychain.KeychainError.unexpectedStatus(errSecAuthFailed),
            failingAccounts: [accessAccount]
        )
        fixture.values[refreshAccount] = "old-refresh"
        fixture.values[accessAccount] = "old-access"
        let store = TokenStore(accountID: accountID, keychain: fixture.client)
        let tokens = GoogleTokens(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            expiresAt: Date(timeIntervalSince1970: 1_234)
        )

        XCTAssertThrowsError(try store.save(tokens: tokens))

        XCTAssertEqual(fixture.values[refreshAccount], "old-refresh")
        XCTAssertEqual(fixture.values[accessAccount], "old-access")
    }

    private static func refreshAccount(_ accountID: UUID) -> String {
        "mailbell.account.\(accountID.uuidString).gmail.refreshToken"
    }

    private static func accessAccount(_ accountID: UUID) -> String {
        "mailbell.account.\(accountID.uuidString).gmail.accessToken"
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
