import Foundation

/// An error from reading or changing the provider settings.
nonisolated enum ProvidersError: LocalizedError, Equatable {
    case selectionUnreadable
    case selectionUnsaved
    /// The custom RPC's deletion couldn't be saved.
    case deletionUnsaved

    var errorDescription: String? {
        switch self {
        case .selectionUnreadable: String(localized: "Couldn't Load Provider")
        case .selectionUnsaved: String(localized: "Couldn't Change Provider")
        case .deletionUnsaved: String(localized: "Couldn't Delete RPC")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .selectionUnreadable: String(localized: "Your provider choice couldn't be loaded.")
        case .selectionUnsaved: String(localized: "Your provider choice couldn't be saved on this device. Try again.")
        case .deletionUnsaved: String(localized: "The RPC couldn't be deleted from this device. Try again.")
        }
    }
}
