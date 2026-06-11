@testable import mailbell
import XCTest

final class AccountSupervisorTests: XCTestCase {
    @MainActor
    func testConnectedStatusClearsPreviousAccountError() async {
        let (supervisor, account) = makeSupervisor()

        supervisor.monitor(
            account.id,
            didChangeStatus: .reconnecting,
            error: "Token refresh unavailable: The Internet connection appears to be offline."
        )
        await Task.yield()

        XCTAssertEqual(
            supervisor.accountStates.first?.lastError,
            "Token refresh unavailable: The Internet connection appears to be offline."
        )

        supervisor.monitor(account.id, didChangeStatus: .connected, error: nil)
        await Task.yield()

        XCTAssertNil(supervisor.accountStates.first?.lastError)
    }

    @MainActor
    func testConnectingStatusDoesNotClearPreviousAccountError() async {
        let (supervisor, account) = makeSupervisor()

        supervisor.monitor(
            account.id,
            didChangeStatus: .reconnecting,
            error: "Token refresh unavailable: The Internet connection appears to be offline."
        )
        await Task.yield()

        supervisor.monitor(account.id, didChangeStatus: .connecting, error: nil)
        await Task.yield()

        XCTAssertEqual(
            supervisor.accountStates.first?.lastError,
            "Token refresh unavailable: The Internet connection appears to be offline."
        )
    }

    @MainActor
    func testConnectedStatusDoesNotClearNotificationError() async {
        let (supervisor, account) = makeSupervisor()

        supervisor.monitor(
            account.id,
            didNotify: makeHeader(),
            result: .unavailable("Notifications unavailable outside app bundle.")
        )
        await Task.yield()

        supervisor.monitor(account.id, didChangeStatus: .connected, error: nil)
        await Task.yield()

        XCTAssertEqual(
            supervisor.accountStates.first?.lastError,
            "Notifications unavailable outside app bundle."
        )
    }

    @MainActor
    func testPostedNotificationClearsPreviousNotificationError() async {
        let (supervisor, account) = makeSupervisor()

        supervisor.monitor(
            account.id,
            didNotify: makeHeader(),
            result: .unavailable("Notifications unavailable outside app bundle.")
        )
        await Task.yield()

        supervisor.monitor(account.id, didNotify: makeHeader(), result: .posted)
        await Task.yield()

        XCTAssertNil(supervisor.accountStates.first?.lastError)
    }

    @MainActor
    func testOAuthSetupMessageUsesConfigProviderError() {
        let (supervisor, _) = makeSupervisor(configProvider: { throw OAuthConfigIssue.missingCredentials })

        XCTAssertEqual(
            supervisor.oauthSetupMessage,
            OAuthConfigIssue.missingCredentials.localizedDescription
        )
    }

    @MainActor
    private func makeSupervisor(
        configProvider: @escaping () throws -> OAuthConfig = {
            OAuthConfig(
                clientID: "dummy-local-client-id.apps.googleusercontent.com",
                clientSecret: "dummy-local-client-secret"
            )
        }
    ) -> (AccountSupervisor, MailAccount) {
        let suiteName = "mailbell.AccountSupervisorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = AccountStore(userDefaults: defaults)
        let account = MailAccount(providerID: .gmail, email: "test@example.com")
        store.saveAccounts([account])
        let supervisor = AccountSupervisor(
            configProvider: configProvider,
            accountStore: store
        )
        return (supervisor, account)
    }

    private func makeHeader() -> MessageHeader {
        MessageHeader(uid: 1, from: "sender@example.com", subject: "Subject", date: "", gmThreadId: nil)
    }
}
