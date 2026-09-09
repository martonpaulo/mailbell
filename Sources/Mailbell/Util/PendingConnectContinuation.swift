import Foundation

/// Owns the single completion of an in-progress connect.
///
/// Network.framework can report readiness, failure, or cancellation, and a
/// cancel issued before any of them may produce no callback at all. Holding the
/// continuation here rather than inside the state handler lets cancellation
/// finish the attempt itself, so a cancelled connect fails instead of hanging —
/// and the nil-out under the lock is what guarantees exactly one resume when
/// two of those outcomes race.
final class PendingConnectContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    /// True while an attempt is waiting to be finished.
    var isPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return continuation != nil
    }

    func store(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        self.continuation = continuation
    }

    /// Resumes the stored continuation, if any, and clears it. Later calls do
    /// nothing, so racing outcomes cannot resume twice.
    /// - Returns: whether this call was the one that finished the attempt.
    @discardableResult
    func finish(throwing error: Error?) -> Bool {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        guard let continuation else { return false }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
        return true
    }
}
