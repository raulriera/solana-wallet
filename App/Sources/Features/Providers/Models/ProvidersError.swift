import Foundation

/// A secret-free error that Providers explains in an alert.
nonisolated enum ProvidersError: LocalizedError, Equatable {
    /// The provider choice couldn't be read.
    case selectionUnreadable
    /// The provider choice couldn't be saved.
    case selectionUnsaved

    /// The alert's title.
    var errorDescription: String? {
        switch self {
        case .selectionUnreadable: String(localized: "Couldn't Load Provider")
        case .selectionUnsaved: String(localized: "Couldn't Change Provider")
        }
    }

    /// The alert's explanation.
    var recoverySuggestion: String? {
        switch self {
        case .selectionUnreadable: String(localized: "Your provider choice couldn't be loaded.")
        case .selectionUnsaved: String(localized: "Your provider choice couldn't be saved on this device. Try again.")
        }
    }
}
