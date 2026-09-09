import Foundation
@testable import mailbell
import XCTest

/// A run suspends on the network several times. Cancelling its task does not
/// stop the resumed continuation from assigning a client or publishing status,
/// so a stopped or superseded run could still take the account back.
@MainActor
final class MailMonitorRunGenerationTests: XCTestCase {
    func testAStoppedRunIsRetiredWhileItIsStillSuspended() async {
        let monitor = makeMonitor()
        let recorder = StatusRecorder()
        monitor.delegate = recorder

        let suspended = Suspension()
        monitor.accessTokenSource = { [suspended] in
            await suspended.wait()
            return "token"
        }

        monitor.start()
        let generation = monitor.currentRunGeneration
        await suspended.waitUntilEntered()

        monitor.stop()
        XCTAssertFalse(
            monitor.isCurrentRun(generation),
            "stop must retire the generation, not only cancel the task"
        )

        // Let the old run resume out of token retrieval.
        suspended.release()
        await Task.yield()

        XCTAssertFalse(monitor.isCurrentRun(generation))
    }

    func testRestartingSupersedesTheRunThatWasSuspended() async {
        let monitor = makeMonitor()
        monitor.delegate = StatusRecorder()

        let suspended = Suspension()
        monitor.accessTokenSource = { [suspended] in
            await suspended.wait()
            return "token"
        }

        monitor.start()
        let first = monitor.currentRunGeneration
        await suspended.waitUntilEntered()

        monitor.start()
        let second = monitor.currentRunGeneration

        XCTAssertNotEqual(first, second)
        XCTAssertFalse(monitor.isCurrentRun(first), "the overtaken run must not own the account")
        XCTAssertTrue(monitor.isCurrentRun(second))

        suspended.release()
    }

    func testAStoppedRunPublishesNoFurtherStatus() async {
        let monitor = makeMonitor()
        let recorder = StatusRecorder()
        monitor.delegate = recorder

        let suspended = Suspension()
        monitor.accessTokenSource = { [suspended] in
            await suspended.wait()
            return "token"
        }

        monitor.start()
        await suspended.waitUntilEntered()
        monitor.stop()
        let afterStop = recorder.statuses

        suspended.release()
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        XCTAssertEqual(
            recorder.statuses,
            afterStop,
            "a retired run must not report connecting or connected afterwards"
        )
        XCTAssertEqual(recorder.statuses.last, .signedOut, "stop is the last word on this account")
    }

    // MARK: - Helpers

    private func makeMonitor() -> MailMonitor {
        MailMonitor(
            account: MailAccount(providerID: .gmail, email: "account@example.com"),
            config: OAuthConfig(
                clientID: "dummy-local-client-id.apps.googleusercontent.com",
                clientSecret: "dummy-local-client-secret"
            )
        )
    }
}

/// Holds a run open at a chosen suspension point until the test lets it go.
private actor SuspensionState {
    private(set) var isReleased = false
    private(set) var didEnter = false

    func markEntered() { didEnter = true }
    func release() { isReleased = true }
}

private struct Suspension: Sendable {
    private let state = SuspensionState()

    func wait() async {
        await state.markEntered()
        while await !state.isReleased {
            await Task.yield()
        }
    }

    func waitUntilEntered() async {
        for _ in 0 ..< 500 where await !state.didEnter {
            await Task.yield()
        }
    }

    func release() {
        Task { await state.release() }
    }
}

private final class StatusRecorder: MailMonitorDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [MonitorStatus] = []

    var statuses: [MonitorStatus] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    nonisolated func monitor(_: UUID, didChangeStatus status: MonitorStatus, error _: String?) {
        lock.lock()
        recorded.append(status)
        lock.unlock()
    }

    nonisolated func monitor(_: UUID, shouldNotify headers: [MessageHeader]) async -> Set<IMAPMessageIdentity> {
        Set(headers.compactMap(\.imapIdentity))
    }

    nonisolated func monitor(_: UUID, didNotify _: MessageHeader, result _: NotificationPostResult) {}

    nonisolated func monitor(
        _: UUID,
        uidsToSkipFor _: MessageMailbox,
        mailboxName _: String,
        uidValidity _: Int
    ) async -> Set<Int> {
        []
    }

    nonisolated func monitor(
        _: UUID,
        didReconcileUnread _: [MailboxUnreadSnapshot],
        fetchedHeaders _: [MessageHeader]
    ) async {}
}
