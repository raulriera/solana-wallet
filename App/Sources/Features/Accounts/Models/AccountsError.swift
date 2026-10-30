import Foundation

/// An error that stops an account from being added, renamed, or deleted.
nonisolated enum AccountsError: RetryableError, Equatable {
    case notAdded
    /// The device doesn't have the wallet's recovery phrase.
    case recoveryUnavailable
    case notRenamed
    case notDeleted

    var canRetry: Bool { self == .notAdded }

    var errorDescription: String? {
        switch self {
        case .notAdded, .recoveryUnavailable: String(localized: "Couldn't Add Account")
        case .notRenamed: String(localized: "Couldn't Rename Account")
        case .notDeleted: String(localized: "Couldn't Delete Account")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notAdded: String(localized: "The new account couldn't be saved on this device. Try again.")
        case .recoveryUnavailable:
            String(localized: "This wallet's recovery phrase is no longer on this device. To add accounts, reset the app and import the phrase again.")
        case .notRenamed: String(localized: "The account's new name couldn't be saved on this device. Try again.")
        case .notDeleted: String(localized: "The account couldn't be deleted from this device. Try again.")
        }
    }
}
