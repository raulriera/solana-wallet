import Foundation

/// A private-balance error that an alert explains.
nonisolated enum PrivateBalanceError: TransactionReviewError, CaseIterable {
    /// The account's derivation path has no private-balance keys.
    case unsupportedAccount
    case registeredWithOtherKeys
    /// This device has no private-balance keys for the account.
    case turnedOff
    /// The network has no private balances, or the selected provider doesn't support them.
    case unavailable
    case recipientUnregistered
    /// The account's spendable private balance doesn't cover the amount.
    case insufficientBalance
    /// The amount needs more of the account's private notes than one transaction spends.
    case tooManyNotes
    /// The account's public SOL doesn't cover the amount and the fees.
    case insufficientPublicBalance
    /// The account's public SOL doesn't cover the fees of moving private SOL to it.
    case insufficientPublicBalanceForFees
    case preparationFailed
    case notSent
    case invalidCode
    case codeForOtherNetwork
    /// The redeem code's SOL was already redeemed or taken back.
    case codeRedeemed
    /// The redeem code's public SOL doesn't cover the fees of redeeming it.
    case codeUnderfunded
    /// The indexer doesn't report the redeem code's private SOL yet.
    case codeNotReady
    /// Turning private balances on failed for another reason.
    case turnOnFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedAccount, .registeredWithOtherKeys, .turnedOff, .unavailable:
            String(localized: "Private Balance Unavailable")
        case .recipientUnregistered, .insufficientBalance, .tooManyNotes:
            String(localized: "Can't Complete Transaction")
        case .insufficientPublicBalance, .insufficientPublicBalanceForFees:
            String(localized: "Not Enough SOL")
        case .preparationFailed:
            String(localized: "Can't Prepare Transaction")
        case .notSent:
            String(localized: "Couldn't Send Transaction")
        case .invalidCode, .codeForOtherNetwork, .codeRedeemed, .codeUnderfunded, .codeNotReady:
            String(localized: "Can't Use Code")
        case .turnOnFailed:
            String(localized: "Couldn't Turn On Private Balance")
        }
    }

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
        case .insufficientPublicBalance:
            String(localized: "Your public balance doesn't cover this amount and the fees. Try a smaller amount.")
        case .insufficientPublicBalanceForFees:
            String(localized: "Your public balance must cover the fees. Add SOL to it, then try again.")
        case .preparationFailed:
            String(localized: "The selected provider couldn't prepare this transaction. Try again.")
        case .notSent:
            String(localized: "Nothing left your wallet. Try again in a moment.")
        case .invalidCode:
            String(localized: "This isn't a valid code. Check that you have the whole code.")
        case .codeForOtherNetwork:
            String(localized: "This code is for another network. Switch networks to use it.")
        case .codeRedeemed:
            String(localized: "This code was already used, or its creator took it back.")
        case .codeUnderfunded:
            String(localized: "This code doesn't hold enough SOL to pay the network fees for using it.")
        case .codeNotReady:
            String(localized: "This code was created moments ago. Try again in a minute.")
        case .turnOnFailed:
            String(localized: "Private balances couldn't be turned on for this account. Try again.")
        }
    }

    var canRetry: Bool { self == .preparationFailed || self == .notSent }
}
