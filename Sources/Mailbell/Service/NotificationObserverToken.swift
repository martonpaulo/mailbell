import AppKit
import Foundation

final class NotificationObserverToken: @unchecked Sendable {
    private let lock = NSLock()
    private var token: NSObjectProtocol?

    func store(_ token: NSObjectProtocol) {
        lock.lock()
        self.token = token
        lock.unlock()
    }

    func remove() {
        lock.lock()
        let token = token
        self.token = nil
        lock.unlock()

        if let token {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }
}
