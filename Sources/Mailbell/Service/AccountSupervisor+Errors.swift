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
                String(localized: "This account no longer exists.")
            case .authenticationInProgress:
                String(localized: "Google sign-in is already in progress.")
            case .accountMismatch(let expected, let actual):
                String(
                    localized: "Signed in as \(actual), but this account is \(expected). Sign in with \(expected).",
                    comment: "The first placeholder is the address signed in; the others are the account's address."
                )
            case .sessionSaveFailed:
                String(localized: "Couldn't save the sign-in to the Keychain. Try again.")
            }
        }
    }
}
