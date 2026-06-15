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
    func webmailURL(for account: MailAccount?) -> URL
    func webmailURL(for header: MessageHeader) -> URL
    func webmailURL(for header: MessageHeader, account: MailAccount?) -> URL
}

struct GmailProvider: MailProvider {
    let id: MailProviderID = .gmail
    var displayName: String {
        id.displayName
    }

    let capabilities = ProviderCapabilities(supportsIdle: true, supportsThreadLink: true)
    let webmailURL = URL(string: "https://mail.google.com/")!

    func webmailURL(for _: MailAccount?) -> URL {
        webmailURL
    }

    func webmailURL(for header: MessageHeader) -> URL {
        webmailURL(for: header, account: nil)
    }

    func webmailURL(for header: MessageHeader, account: MailAccount?) -> URL {
        guard let threadID = header.gmThreadId,
              let threadValue = UInt64(threadID, radix: 10)
        else {
            return webmailURL(for: account)
        }
        let threadHex = String(threadValue, radix: 16)
        return URL(string: "https://mail.google.com/mail/#inbox/\(threadHex)") ?? webmailURL(for: account)
    }
}

enum MailProviderRegistry {
    static func provider(for id: MailProviderID) -> MailProvider {
        switch id {
        case .gmail:
            GmailProvider()
        }
    }
}
