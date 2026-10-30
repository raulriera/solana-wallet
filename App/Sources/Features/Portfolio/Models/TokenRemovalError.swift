import Foundation

/// A reason a token couldn't be removed.
nonisolated enum TokenRemovalError: RetryableError, Equatable {
    /// The saved token list can't be read.
    case listUnreadable
    case saveFailed

    var canRetry: Bool { self == .saveFailed }

    var errorDescription: String? { String(localized: "Couldn't Remove Token") }

    var recoverySuggestion: String? {
        switch self {
        case .listUnreadable: String(localized: "Your token list can't be read, so no token can be removed.")
        case .saveFailed: String(localized: "Your token list couldn't be saved. Try again.")
        }
    }
}
