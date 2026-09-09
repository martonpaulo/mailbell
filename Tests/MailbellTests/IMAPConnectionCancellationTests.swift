@testable import mailbell
import XCTest

/// Cancelling an IMAP connection used to remove the state handler *before*
/// cancelling, so the `.cancelled` callback that owned every completion of
/// `connect()` never fired and the monitor stayed suspended forever.
final class IMAPConnectionCancellationTests: XCTestCase {
    func testCancelBeforeReadinessFinishesTheAttemptAsClosed() async throws {
        // 192.0.2.0/24 is TEST-NET-1 (RFC 5737): it goes nowhere, so readiness
        // cannot arrive and only cancellation can finish this attempt.
        let connection = IMAPConnection(host: "192.0.2.1", port: 993)
        let connected = Task { try await connection.connect() }

        // Give the attempt a moment to suspend before cancelling it.
        try await Task.sleep(nanoseconds: 100_000_000)
        connection.cancel()

        do {
            _ = try await withTimeout(seconds: 5) { try await connected.value }
            XCTFail("expected the cancelled attempt to fail")
        } catch is IMAPConnection.ConnectionError {
            // Cancellation resolved it, which is the point of the fix.
        } catch let error as TimeoutError {
            XCTFail("connect() stayed suspended after cancel: \(error)")
        }
    }

    func testRepeatedConnectAndCancelCyclesAllFinish() async throws {
        for _ in 0 ..< 5 {
            let connection = IMAPConnection(host: "192.0.2.1", port: 993)
            let connected = Task { try await connection.connect() }
            try await Task.sleep(nanoseconds: 20_000_000)
            connection.cancel()

            do {
                _ = try await withTimeout(seconds: 5) { try await connected.value }
            } catch is TimeoutError {
                return XCTFail("a cancelled attempt accumulated as a suspended task")
            } catch {
                // Any thrown outcome is a finished attempt.
            }
        }
    }

    // MARK: - The one-shot completion itself

    func testFinishResumesExactlyOnceAcrossRacingOutcomes() async throws {
        let pending = PendingConnectContinuation()
        let finishedCount = Counter()

        async let outcome: Void = withCheckedThrowingContinuation { continuation in
            pending.store(continuation)
            // Ready, failed and cancelled can all arrive; only one may resume.
            DispatchQueue.global().async {
                if pending.finish(throwing: nil) { finishedCount.increment() }
            }
            DispatchQueue.global().async {
                if pending.finish(throwing: IMAPConnection.ConnectionError.closed) { finishedCount.increment() }
            }
            DispatchQueue.global().async {
                if pending.finish(throwing: IMAPConnection.ConnectionError.notReady("x")) { finishedCount.increment() }
            }
        }

        _ = try? await outcome
        // Let the losing callers run before counting.
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(finishedCount.value, 1)
        XCTAssertFalse(pending.isPending)
    }

    func testFinishWithoutAPendingAttemptDoesNothing() {
        let pending = PendingConnectContinuation()

        XCTAssertFalse(pending.isPending)
        XCTAssertFalse(pending.finish(throwing: nil))
    }

    // MARK: - Helpers

    private struct TimeoutError: Error {}

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func increment() {
            lock.lock()
            count += 1
            lock.unlock()
        }
    }

    private func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            guard let result = try await group.next() else { throw TimeoutError() }
            group.cancelAll()
            return result
        }
    }
}
