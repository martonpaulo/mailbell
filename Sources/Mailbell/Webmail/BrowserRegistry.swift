import AppKit
import Foundation

enum BrowserRegistry {
    static let chromeBundleID = "com.google.Chrome"

    private static let browserBundleAllowlist: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        chromeBundleID,
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "com.google.Chrome.canary",
        "com.chromium.Chromium"
    ]

    static func browsers(for url: URL = MailProviderRegistry.provider(for: .gmail).webmailURL) -> [BrowserCandidate] {
        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: url)
        var seenBundleIDs = Set<String>()
        var candidates: [BrowserCandidate] = [.systemDefault]

        for appURL in appURLs {
            guard let bundle = Bundle(url: appURL),
                  let bundleID = bundle.bundleIdentifier,
                  browserBundleAllowlist.contains(bundleID),
                  seenBundleIDs.insert(bundleID).inserted else {
                continue
            }

            let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? appURL.deletingPathExtension().lastPathComponent

            candidates.append(
                BrowserCandidate(
                    id: bundleID,
                    displayName: displayName,
                    bundleIdentifier: bundleID,
                    appURL: appURL,
                    supportsChromeProfiles: bundleID == chromeBundleID
                )
            )
        }

        return candidates.sorted { left, right in
            if left.id == BrowserCandidate.systemDefaultID { return true }
            if right.id == BrowserCandidate.systemDefaultID { return false }
            return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
        }
    }

    static func candidate(
        matching preference: WebmailOpenPreference?,
        browsers: [BrowserCandidate]
    ) -> BrowserCandidate {
        guard let preference else { return .systemDefault }
        switch preference.browser {
        case .systemDefault:
            return .systemDefault
        case let .application(bundleIdentifier, appPath):
            if let match = browsers.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
                return match
            }
            let appURL = URL(fileURLWithPath: appPath)
            let displayName = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? appURL.deletingPathExtension().lastPathComponent
            return BrowserCandidate(
                id: bundleIdentifier,
                displayName: displayName,
                bundleIdentifier: bundleIdentifier,
                appURL: appURL,
                supportsChromeProfiles: bundleIdentifier == chromeBundleID
            )
        }
    }

    static func browserOptions(
        matching preference: WebmailOpenPreference?,
        browsers: [BrowserCandidate]
    ) -> [BrowserCandidate] {
        let selected = candidate(matching: preference, browsers: browsers)
        guard !browsers.contains(where: { $0.id == selected.id }) else { return browsers }
        return browsers + [selected]
    }

    static func preference(
        for candidate: BrowserCandidate,
        chromeProfileDirectory: String?
    ) -> WebmailOpenPreference? {
        guard candidate.id != BrowserCandidate.systemDefaultID else { return nil }
        guard let bundleIdentifier = candidate.bundleIdentifier,
              let appPath = candidate.appURL?.standardizedFileURL.path else {
            return nil
        }
        var profile = chromeProfileDirectory
        if bundleIdentifier != chromeBundleID {
            profile = nil
        }
        return WebmailOpenPreference(
            browser: .application(bundleIdentifier: bundleIdentifier, appPath: appPath),
            chromeProfileDirectory: profile
        )
    }
}
