import Foundation
import AppKit

/// Network availability and sleep/wake. These force a reconnect rather than
/// polling, which is the whole point of the IDLE model.
extension AccountSupervisor {
    func setupNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                self?.handlePathUpdate(satisfied: satisfied)
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    func handlePathUpdate(satisfied: Bool) {
        let recovered = satisfied && !lastPathSatisfied
        lastPathSatisfied = satisfied
        if recovered {
            Log.info("Network recovered; forcing account reconnects.")
            forceReconnectAll()
        }
    }

    func setupSleepWakeObservers() {
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                Log.info("System woke; forcing account reconnects.")
                self?.forceReconnectAll()
            }
        }
        wakeObserver.store(token)
    }
}
