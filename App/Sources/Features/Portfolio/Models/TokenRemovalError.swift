import Foundation

/// Why a token couldn't be removed, explained in an alert; the token stays in the list.
nonisolated enum TokenRemovalError: RetryableError, Equatable {
    /// The saved token list can't be read, so no token can be removed.
    case listUnreadable
    /// The token list couldn't be saved.
    case saveFailed

    /// Whether trying again can help; a readable list can't come from a retry.
    var canRetry: Bool { self == .saveFailed }

    /// The alert's title.
    var errorDescription: String? { String(localized: "Couldn't Remove Token") }

    /// What went wrong and what to do about it.
    var recoverySuggestion: String? {
        switch self {
        case .listUnreadable: String(localized: "Your token list can't be read, so no token can be removed.")
        case .saveFailed: String(localized: "Your token list couldn't be saved. Try again.")
        }
    }
}
