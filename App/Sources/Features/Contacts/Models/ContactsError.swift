import Foundation

/// An error that stops a change to contacts from being saved.
nonisolated enum ContactsError: LocalizedError, Equatable {
    case unsaved

    var errorDescription: String? { String(localized: "Couldn't Save Change") }

    var recoverySuggestion: String? { String(localized: "Your change to Contacts couldn't be saved. Try again.") }
}
