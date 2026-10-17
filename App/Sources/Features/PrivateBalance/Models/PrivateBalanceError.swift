import Foundation

/// A private-balance error that the app explains in an alert, without keys or underlying errors.
nonisolated enum PrivateBalanceError: LocalizedError, Equatable, CaseIterable {
    /// The account's derivation path has no private-balance keys; only standard Solana accounts have them.
    case unsupportedAccount
    /// The account registered other private-balance keys, such as another app's, so this app can't read its notes.
    case registeredWithOtherKeys
    /// Private balances aren't turned on for the account: this device has no keys for it.
    case turnedOff
    /// The network has no private balances, or the selected provider doesn't support them.
    case unavailable
    /// The recipient hasn't turned on private balances, so only a regular payment can reach them.
    case recipientUnregistered
    /// The account's spendable private balance doesn't cover the amount.
    case insufficientBalance
    /// The amount needs more of the account's private notes than one transaction spends.
    case tooManyNotes

    /// The alert's title.
    var errorDescription: String? {
        switch self {
        case .unsupportedAccount, .registeredWithOtherKeys, .turnedOff, .unavailable:
            String(localized: "Private Balance Unavailable")
        case .recipientUnregistered, .insufficientBalance, .tooManyNotes:
            String(localized: "Can't Complete Transaction")
        }
    }

    /// The alert's explanation.
    var recoverySuggestion: String? {
        switch self {
        case .unsupportedAccount:
            String(localized: "Private balances aren't available for this kind of account.")
        case .registeredWithOtherKeys:
            String(localized: "This account turned on private balances in another app, so this app can't read them.")
        case .turnedOff:
            String(localized: "Turn on private balances for this account first.")
        case .unavailable:
            String(localized: "Private balances aren't available on this network with the selected provider.")
        case .recipientUnregistered:
            String(localized: "This person hasn't turned on private balances. You can send a regular payment instead.")
        case .insufficientBalance:
            String(localized: "Your private balance doesn't cover this amount. Recently received funds can take a moment to become available.")
        case .tooManyNotes:
            String(localized: "This amount combines too many private payments for one transaction. Try a smaller amount.")
        }
    }
}
