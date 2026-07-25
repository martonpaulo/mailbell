import Foundation
import Sparkle
import SwiftUI

/// Wraps Sparkle for the direct-download build. The updater only starts from a
/// real installed bundle that ships both a feed URL and a public key, so
/// `swift run` and unsigned local builds stay completely inert and never reach
/// the network.
@MainActor
final class UpdateManager: ObservableObject {
    nonisolated static let feedURLKey = "SUFeedURL"
    nonisolated static let publicKeyKey = "SUPublicEDKey"

    @Published private(set) var automaticallyChecksForUpdates: Bool

    private let controller: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        let feed = (bundle.object(forInfoDictionaryKey: Self.feedURLKey) as? String) ?? ""
        let key = (bundle.object(forInfoDictionaryKey: Self.publicKeyKey) as? String) ?? ""
        if Self.isUpdatable(feedURL: feed, publicKey: key), AppIdentity.isPackagedApp {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
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

/// One home for the version string shown in Settings, the About pane, and bug
/// reports.
enum AppVersion {
    static func text(bundle: Bundle = .main) -> String {
        let info = bundle.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (info?["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let displayVersion = (version?.isEmpty == false) ? version! : "Development"
        guard let build, !build.isEmpty, build != displayVersion else {
            return displayVersion
        }
        return "\(displayVersion) (\(build))"
    }

    static var displayText: String {
        text()
    }
}
