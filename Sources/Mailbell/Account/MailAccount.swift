import Foundation

enum MailProviderID: String, Codable, CaseIterable {
    case gmail

    var displayName: String {
        switch self {
        case .gmail:
            return "Google Gmail"
        }
    }
}

struct MailAccount: Identifiable, Codable, Equatable {
    let id: UUID
    var providerID: MailProviderID
    var email: String
    var displayName: String?
    var isEnabled: Bool
    var createdAt: Date
    var webmailOpenPreference: WebmailOpenPreference?

    init(
        id: UUID = UUID(),
        providerID: MailProviderID,
        email: String,
        displayName: String? = nil,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        webmailOpenPreference: WebmailOpenPreference? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.email = email
        self.displayName = displayName
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.webmailOpenPreference = webmailOpenPreference
    }
}

struct AccountRuntimeState: Identifiable, Equatable {
    var account: MailAccount
    var status: MonitorStatus
    var lastError: String?
    var webmailOpenError: String?

    var id: UUID { account.id }
}
