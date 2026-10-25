import Foundation

/// Why a change to Settings > Accounts couldn't be made, explained in an alert; the list keeps what's saved.
nonisolated enum AccountsError: RetryableError, Equatable {
    /// A new account couldn't be derived or saved.
    case notAdded
    /// This device no longer has the wallet's recovery phrase, so no account can be derived from it.
    case recoveryUnavailable
    /// An account's new name couldn't be saved.
    case notRenamed
    /// An account couldn't be deleted.
    case notDeleted

    /// Whether the alert repeats the change; only an addition does, since a rename keeps the typed name on screen to
    /// save again, a deleted account's row stays to delete again, and a missing recovery phrase stays missing.
    var canRetry: Bool { self == .notAdded }

    /// The alert's title.
    var errorDescription: String? {
        switch self {
        case .notAdded, .recoveryUnavailable: String(localized: "Couldn't Add Account")
        case .notRenamed: String(localized: "Couldn't Rename Account")
        case .notDeleted: String(localized: "Couldn't Delete Account")
        }
    }

    /// What went wrong and what to do about it.
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
