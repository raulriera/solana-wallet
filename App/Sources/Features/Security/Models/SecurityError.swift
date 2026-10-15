import Foundation

/// A secret-free error that Security & Privacy explains in an alert.
nonisolated enum SecurityError: RetryableError, Equatable {
    /// The recovery couldn't be read.
    case recoveryUnreadable
    /// The device owner didn't authenticate.
    case ownerNotConfirmed
    /// A reset stopped before deleting everything.
    case resetIncomplete

    /// Whether trying again can help; only an incomplete reset repeats from its alert.
    var canRetry: Bool { self == .resetIncomplete }

    /// The alert's title.
    var errorDescription: String? {
        switch self {
        case .recoveryUnreadable: String(localized: "Couldn't Show Recovery Phrase")
        case .ownerNotConfirmed: String(localized: "Couldn't Confirm It's You")
        case .resetIncomplete: String(localized: "Couldn't Reset App")
        }
    }

    /// The alert's explanation.
    var recoverySuggestion: String? {
        switch self {
        case .recoveryUnreadable: String(localized: "Your recovery phrase couldn't be read. Try again.")
        case .ownerNotConfirmed: String(localized: "Try again.")
        case .resetIncomplete: String(localized: "Some data may already be deleted. Try again to finish the reset.")
        }
    }
}
