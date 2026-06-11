import Foundation

extension AccountSupervisor {
    enum SupervisorError: LocalizedError {
        case missingAccount
        case authenticationInProgress
        case accountMismatch(expected: String, actual: String)
        case sessionSaveFailed

        var errorDescription: String? {
            switch self {
            case .missingAccount:
                "Account not found."
            case .authenticationInProgress:
                "Google sign-in is already in progress."
            case let .accountMismatch(expected, actual):
                "Signed in as \(actual), but this account expects \(expected)."
            case .sessionSaveFailed:
                "Could not save Google sign-in in Keychain. Check Keychain access and try again."
            }
        }
    }
}
