import Foundation

final class AccountStore {
    enum AccountStoreError: Error, LocalizedError {
        case decodingFailed(String)
        case encodingFailed(String)
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case let .decodingFailed(detail):
                "Could not read saved accounts: \(detail)"
            case let .encodingFailed(detail):
                "Could not encode accounts for storage: \(detail)"
            case let .saveFailed(detail):
                "Could not save accounts: \(detail)"
            }
        }
    }

    private let userDefaults: UserDefaults
    private let accountsKey = "mailbell.accounts"
    private let saveData: (_ data: Data, _ key: String) throws -> Void

    init(
        userDefaults: UserDefaults = .standard,
        saveData: ((_ data: Data, _ key: String) throws -> Void)? = nil
    ) {
        self.userDefaults = userDefaults
        self.saveData = saveData ?? { [userDefaults] data, key in
            userDefaults.set(data, forKey: key)
        }
    }

    func loadAccounts() throws -> [MailAccount] {
        guard let data = userDefaults.data(forKey: accountsKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([MailAccount].self, from: data)
        } catch {
            throw AccountStoreError.decodingFailed(error.localizedDescription)
        }
    }

    func saveAccounts(_ accounts: [MailAccount]) throws {
        do {
            let data = try JSONEncoder().encode(accounts)
            do {
                try saveData(data, accountsKey)
            } catch let error as AccountStoreError {
                throw error
            } catch {
                throw AccountStoreError.saveFailed(error.localizedDescription)
            }
        } catch let error as AccountStoreError {
            throw error
        } catch {
            throw AccountStoreError.encodingFailed(error.localizedDescription)
        }
    }

    func upsert(_ account: MailAccount) throws -> [MailAccount] {
        var accounts = try loadAccounts()
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        try saveAccounts(accounts)
        return accounts
    }

    func remove(accountID: UUID) throws -> [MailAccount] {
        let accounts = try loadAccounts().filter { $0.id != accountID }
        try saveAccounts(accounts)
        return accounts
    }
}
