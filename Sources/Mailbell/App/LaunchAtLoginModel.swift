import Foundation

/// The General pane's launch-at-login state: the login-item status macOS
/// reports, plus whether the last requested change failed.
///
/// `refresh()` only reads. It runs when Settings appears and when Mailbell
/// becomes active, so a change made in System Settings shows up without
/// polling, and opening Settings can never register a login item.
/// `request(_:)` is the only path that changes the registration.
@MainActor
@Observable
final class LaunchAtLoginModel {
    private(set) var status: LoginItemStatus
    private(set) var failed = false

    @ObservationIgnored private let readStatus: () -> LoginItemStatus
    @ObservationIgnored private let change: (Bool) -> LoginItemChange
    @ObservationIgnored private let openLoginItemsSettingsAction: () -> Void

    init(
        readStatus: @escaping () -> LoginItemStatus = { LoginItem.status },
        change: @escaping (Bool) -> LoginItemChange = { LoginItem.set($0) },
        openLoginItemsSettings: @escaping () -> Void = { LoginItem.openLoginItemsSettings() }
    ) {
        self.readStatus = readStatus
        self.change = change
        openLoginItemsSettingsAction = openLoginItemsSettings
        status = readStatus()
    }

    /// A status that changed since a failed request supersedes its note.
    func refresh() {
        let current = readStatus()
        guard current != status else { return }
        status = current
        failed = false
    }

    func request(_ isOn: Bool) {
        let result = change(isOn)
        status = result.status
        failed = result.failed
    }

    func openLoginItemsSettings() {
        openLoginItemsSettingsAction()
    }
}
