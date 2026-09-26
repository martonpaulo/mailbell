import Foundation

public final class AccountStore {
    public enum AccountStoreError: Error, LocalizedError {
        case decodingFailed(String)
        case encodingFailed(String)
        case saveFailed(String)

        public var errorDescription: String? {
            switch self {
            // The technical detail stays in the case for the log (Log.detail).
            case .decodingFailed:
                String(localized: "Couldn't read saved accounts.")
            case .encodingFailed, .saveFailed:
                String(localized: "Couldn't save accounts. Try again.")
            }
        }
    }

    private let userDefaults: UserDefaults
    private let saveData: (_ data: Data, _ key: String) throws -> Void

    public init(
        userDefaults: UserDefaults = .standard,
        saveData: ((_ data: Data, _ key: String) throws -> Void)? = nil
    ) {
        self.userDefaults = userDefaults
        self.saveData =
            saveData ?? { [userDefaults] data, key in
                userDefaults.set(data, forKey: key)
            }
    }

    public func loadAccounts() throws -> [MailAccount] {
        guard let data = userDefaults.data(forKey: StorageKeys.accounts) else {
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
                try saveData(data, StorageKeys.accounts)
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

    public func upsert(_ account: MailAccount) throws -> [MailAccount] {
        var accounts = try loadAccounts()
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        try saveAccounts(accounts)
        return accounts
    }

    public func remove(accountID: UUID) throws -> [MailAccount] {
        let accounts = try loadAccounts().filter { $0.id != accountID }
        try saveAccounts(accounts)
        return accounts
    }
}
