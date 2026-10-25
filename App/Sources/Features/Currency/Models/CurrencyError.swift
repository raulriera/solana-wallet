import Foundation

/// An error that the Currency settings explain.
nonisolated enum CurrencyError: LocalizedError, Equatable {
    /// The currency choice couldn't be read.
    case settingsUnreadable
    /// The currency choice couldn't be saved.
    case settingsUnsaved
    /// The rate source's currencies couldn't be loaded.
    case ratesUnavailable

    /// The error's title.
    var errorDescription: String? {
        switch self {
        case .settingsUnreadable: String(localized: "Couldn't Load Currency")
        case .settingsUnsaved: String(localized: "Couldn't Change Currency")
        case .ratesUnavailable: String(localized: "Couldn't Load Exchange Rates")
        }
    }

    /// The error's explanation.
    var recoverySuggestion: String? {
        switch self {
        case .settingsUnreadable: String(localized: "Your currency choice couldn't be loaded.")
        case .settingsUnsaved: String(localized: "Your currency choice couldn't be saved on this device. Try again.")
        case .ratesUnavailable: String(localized: "The exchange rates couldn't be loaded. Try again later.")
        }
    }
}
