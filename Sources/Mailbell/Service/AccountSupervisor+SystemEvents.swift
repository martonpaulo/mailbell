import Foundation
import AppKit
import Network

/// Network availability and sleep/wake. These force a reconnect rather than
/// polling, which is the whole point of the IDLE model.
extension AccountSupervisor {
    func setupNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = Self.pathUpdateHandler { [weak self] satisfied in
            self?.handlePathUpdate(satisfied: satisfied)
        }
        pathMonitor.start(queue: pathQueue)
    }

    /// Nonisolated: NWPathMonitor calls the handler on `pathQueue`.
    nonisolated static func pathUpdateHandler(
        deliver: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> @Sendable (NWPath) -> Void {
        { path in reportPathStatus(satisfied: path.status == .satisfied, to: deliver) }
    }

    /// Nonisolated: runs on `pathQueue` and hands the status to the main actor.
    nonisolated static func reportPathStatus(
        satisfied: Bool,
        to deliver: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        Task { @MainActor in
            deliver(satisfied)
        }
    }

    func handlePathUpdate(satisfied: Bool) {
        let recovered = satisfied && !lastPathSatisfied
        lastPathSatisfied = satisfied
        if recovered {
            Log.monitor.info("Network recovered; forcing account reconnects.")
            forceReconnectAll()
        }
    }

    func setupSleepWakeObservers() {
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main,
            using: Self.wakeHandler { [weak self] in
                Log.monitor.info("System woke; forcing account reconnects.")
                self?.forceReconnectAll()
            }
        )
        wakeObserver.store(token)
    }

    /// Nonisolated: NotificationCenter runs the observer block on the queue it
    /// was given, which the compiler cannot see.
    nonisolated static func wakeHandler(
        deliver: @escaping @MainActor @Sendable () -> Void
    ) -> @Sendable (Notification) -> Void {
        { _ in
            Task { @MainActor in
                deliver()
            }
        }
    }
}
