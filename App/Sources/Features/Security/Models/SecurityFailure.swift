import Foundation

/// A secret-free failure that Security & Privacy explains in an alert.
enum SecurityFailure: Equatable {
    /// The recovery couldn't be read.
    case recoveryUnreadable
    /// The device owner didn't authenticate.
    case ownerNotConfirmed
    /// A reset stopped before deleting everything.
    case resetIncomplete

    /// The alert's title.
    var title: LocalizedStringResource {
        switch self {
        case .recoveryUnreadable: "Couldn't Show Recovery Phrase"
        case .ownerNotConfirmed: "Couldn't Confirm It's You"
        case .resetIncomplete: "Couldn't Reset App"
        }
    }

    /// The alert's explanation.
    var message: LocalizedStringResource {
        switch self {
        case .recoveryUnreadable: "Your recovery phrase couldn't be read. Try again."
        case .ownerNotConfirmed: "Try again."
        case .resetIncomplete: "Some data may already be deleted. Try again to finish the reset."
        }
    }
}
