import Foundation

/// Why a change to Contacts couldn't be saved, explained in an alert; the list returns to what's saved.
nonisolated enum ContactsError: LocalizedError, Equatable {
    /// A new, edited, deleted, or favorite contact couldn't be saved.
    case unsaved

    /// The alert's title.
    var errorDescription: String? { String(localized: "Couldn't Save Change") }

    /// What went wrong and what to do about it.
    var recoverySuggestion: String? { String(localized: "Your change to Contacts couldn't be saved. Try again.") }
}
