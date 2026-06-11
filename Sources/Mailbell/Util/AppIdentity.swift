import Foundation

enum AppIdentity {
    private static let fallbackBundleIdentifier = "dev.mailbell.local"

    static var bundleIdentifier: String {
        let candidate = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let candidate, !candidate.isEmpty else {
            return fallbackBundleIdentifier
        }
        return candidate
    }

    static var keychainService: String {
        bundleIdentifier
    }

    static func dispatchQueueLabel(_ component: String) -> String {
        "\(bundleIdentifier).\(component)"
    }
}
