import Foundation
import Sparkle
import Observation

/// Wraps Sparkle for the direct-download build. The updater only starts from a
/// real installed bundle that ships both a feed URL and a public key, so
/// `swift run` and unsigned local builds stay completely inert and never reach
/// the network.
@MainActor
@Observable
final class UpdateManager {
    nonisolated static let feedURLKey = "SUFeedURL"
    nonisolated static let publicKeyKey = "SUPublicEDKey"

    private(set) var automaticallyChecksForUpdates: Bool

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    /// Sparkle holds its delegates weakly, so the manager owns this one.
    @ObservationIgnored private let userDriverDelegate = UpdateUserDriverDelegate()

    init(bundle: Bundle = .main) {
        let feed = (bundle.object(forInfoDictionaryKey: Self.feedURLKey) as? String) ?? ""
        let key = (bundle.object(forInfoDictionaryKey: Self.publicKeyKey) as? String) ?? ""
        if Self.isUpdatable(feedURL: feed, publicKey: key), AppIdentity.isPackagedApp {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: userDriverDelegate
            )
            self.controller = controller
            automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        } else {
            controller = nil
            automaticallyChecksForUpdates = false
        }
    }

    /// A bundle is updatable only when both halves of the Sparkle contract are
    /// present: where to look, and the key that proves what came back is ours.
    nonisolated static func isUpdatable(feedURL: String, publicKey: String) -> Bool {
        let feed = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !feed.isEmpty, !key.isEmpty else { return false }
        guard let url = URL(string: feed), url.scheme?.lowercased() == "https" else { return false }
        return true
    }

    var isAvailable: Bool {
        controller != nil
    }

    var currentVersion: String {
        AppVersion.displayText
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        guard let controller, automaticallyChecksForUpdates != isEnabled else { return }
        controller.updater.automaticallyChecksForUpdates = isEnabled
        automaticallyChecksForUpdates = isEnabled
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

/// Sparkle's user-driver delegate. `SPUStandardUserDriverDelegate` is an
/// Objective-C protocol, so it needs an `NSObject`; Sparkle calls it on the main
/// thread.
final class UpdateUserDriverDelegate: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    private let alertSizer = UpdateAlertSizer()

    /// The update window then fits its release notes (#75).
    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate else { return }
        alertSizer.fitWhenShown()
    }
}

/// One home for the version string shown in Settings, the About pane, and bug
/// reports.
enum AppVersion {
    static func text(bundle: Bundle = .main) -> String {
        let info = bundle.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (info?["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let displayVersion = if let version, !version.isEmpty { version } else { String(localized: "Development") }
        guard let build, !build.isEmpty, build != displayVersion else {
            return displayVersion
        }
        return "\(displayVersion) (\(build))"
    }

    static var displayText: String {
        text()
    }
}
