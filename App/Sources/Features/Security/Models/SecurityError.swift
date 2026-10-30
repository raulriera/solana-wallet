import Foundation

/// An error in Security & Privacy.
nonisolated enum SecurityError: RetryableError, Equatable {
    case recoveryUnreadable
    case ownerNotConfirmed
    /// A reset that stopped before deleting everything.
    case resetIncomplete

    var canRetry: Bool { self == .resetIncomplete }

    var errorDescription: String? {
        switch self {
        case .recoveryUnreadable: String(localized: "Couldn't Show Recovery Phrase")
        case .ownerNotConfirmed: String(localized: "Couldn't Confirm It's You")
        case .resetIncomplete: String(localized: "Couldn't Reset App")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .recoveryUnreadable: String(localized: "Your recovery phrase couldn't be read. Try again.")
        case .ownerNotConfirmed: String(localized: "Try again.")
        case .resetIncomplete: String(localized: "Some data may already be deleted. Try again to finish the reset.")
        }
    }
}
