import Foundation

/// A private-balance error that the app explains in an alert, without keys or underlying errors.
nonisolated enum PrivateBalanceError: LocalizedError, Equatable, CaseIterable {
    /// The account's derivation path has no private-balance keys; only standard Solana accounts have them.
    case unsupportedAccount
    /// The account registered other private-balance keys, such as another app's, so this app can't read its notes.
    case registeredWithOtherKeys

    /// The alert's title.
    var errorDescription: String? { String(localized: "Private Balance Unavailable") }

    /// The alert's explanation.
    var recoverySuggestion: String? {
        switch self {
        case .unsupportedAccount:
            String(localized: "Private balances aren't available for this kind of account.")
        case .registeredWithOtherKeys:
            String(localized: "This account turned on private balances in another app, so this app can't read them.")
        }
    }
}
