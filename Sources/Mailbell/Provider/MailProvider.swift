import Foundation

struct ProviderCapabilities: Equatable {
    var supportsIdle: Bool
    var supportsThreadLink: Bool
}

protocol MailProvider {
    var id: MailProviderID { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }
    var webmailURL: URL { get }
}

struct GmailProvider: MailProvider {
    let id: MailProviderID = .gmail
    let displayName = "Google Gmail"
    let capabilities = ProviderCapabilities(supportsIdle: true, supportsThreadLink: false)
    let webmailURL = URL(string: "https://mail.google.com/")!
}

enum MailProviderRegistry {
    static func provider(for id: MailProviderID) -> MailProvider {
        switch id {
        case .gmail:
            return GmailProvider()
        }
    }
}
