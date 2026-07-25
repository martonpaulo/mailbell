import Foundation

final class OneShotResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didClaim = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if didClaim {
            return false
        }
        didClaim = true
        return true
    }
}
