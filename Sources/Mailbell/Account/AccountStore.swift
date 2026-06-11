import Foundation

final class AccountStore {
    private let userDefaults: UserDefaults
    private let accountsKey = "mailbell.accounts"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadAccounts() -> [MailAccount] {
        if let data = userDefaults.data(forKey: accountsKey),
           let accounts = try? JSONDecoder().decode([MailAccount].self, from: data) {
            return accounts
        }
        return []
    }

    func saveAccounts(_ accounts: [MailAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        userDefaults.set(data, forKey: accountsKey)
    }

    func upsert(_ account: MailAccount) -> [MailAccount] {
        var accounts = loadAccounts()
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        saveAccounts(accounts)
        return accounts
    }

    func remove(accountID: UUID) -> [MailAccount] {
        let accounts = loadAccounts().filter { $0.id != accountID }
        saveAccounts(accounts)
        return accounts
    }
}
