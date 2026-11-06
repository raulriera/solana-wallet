import Foundation

/// An error from reading or changing the price provider choice.
nonisolated enum PricesError: LocalizedError, Equatable {
    case settingsUnreadable
    case settingsUnsaved
    /// The custom price server's deletion couldn't be saved.
    case deletionUnsaved

    var errorDescription: String? {
        switch self {
        case .settingsUnreadable: String(localized: "Couldn't Load Prices")
        case .settingsUnsaved: String(localized: "Couldn't Change Price Provider")
        case .deletionUnsaved: String(localized: "Couldn't Delete Price Server")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .settingsUnreadable: String(localized: "Your price provider choice couldn't be loaded.")
        case .settingsUnsaved: String(localized: "Your price provider choice couldn't be saved on this device. Try again.")
        case .deletionUnsaved: String(localized: "The price server couldn't be deleted from this device. Try again.")
        }
    }
}
