import Foundation

/// An error in the Currency settings.
nonisolated enum CurrencyError: LocalizedError, Equatable {
    case settingsUnreadable
    case settingsUnsaved
    case ratesUnavailable

    var errorDescription: String? {
        switch self {
        case .settingsUnreadable: String(localized: "Couldn't Load Currency")
        case .settingsUnsaved: String(localized: "Couldn't Change Currency")
        case .ratesUnavailable: String(localized: "Couldn't Load Exchange Rates")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .settingsUnreadable: String(localized: "Your currency choice couldn't be loaded.")
        case .settingsUnsaved: String(localized: "Your currency choice couldn't be saved on this device. Try again.")
        case .ratesUnavailable: String(localized: "The exchange rates couldn't be loaded. Try again later.")
        }
    }
}
