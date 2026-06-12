import Foundation

struct WebmailOpenPreference: Codable, Equatable {
    var browser: BrowserSelection
    var chromeProfileDirectory: String?
}

enum BrowserSelection: Codable, Equatable {
    case systemDefault
    case application(bundleIdentifier: String, appPath: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case bundleIdentifier
        case appPath
    }

    private enum Kind: String, Codable {
        case systemDefault
        case application
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .systemDefault:
            self = .systemDefault
        case .application:
            self = try .application(
                bundleIdentifier: container.decode(String.self, forKey: .bundleIdentifier),
                appPath: container.decode(String.self, forKey: .appPath)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .systemDefault:
            try container.encode(Kind.systemDefault, forKey: .kind)
        case let .application(bundleIdentifier, appPath):
            try container.encode(Kind.application, forKey: .kind)
            try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
            try container.encode(appPath, forKey: .appPath)
        }
    }
}

struct BrowserCandidate: Identifiable, Equatable {
    static let systemDefaultID = "mailbell.systemDefault"

    let id: String
    let displayName: String
    let bundleIdentifier: String?
    let appURL: URL?
    let supportsChromeProfiles: Bool

    static let systemDefault = BrowserCandidate(
        id: systemDefaultID,
        displayName: "System Default",
        bundleIdentifier: nil,
        appURL: nil,
        supportsChromeProfiles: false
    )
}

struct ChromeProfileCandidate: Identifiable, Equatable {
    let directory: String
    let displayName: String
    let userName: String?

    var id: String {
        directory
    }

    var pickerLabel: String {
        if let userName, !userName.isEmpty {
            return "\(displayName) (\(userName))"
        }
        return displayName
    }
}

enum WebmailOpenOutcome: Equatable {
    case opened
    case openedWithFallback(message: String)
    case failed(message: String)

    var didOpen: Bool {
        switch self {
        case .opened, .openedWithFallback:
            true
        case .failed:
            false
        }
    }
}
