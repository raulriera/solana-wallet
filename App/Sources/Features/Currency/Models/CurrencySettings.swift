import Foundation

/// The chosen currency and source of exchange rates.
nonisolated struct CurrencySettings: Codable, Equatable, Sendable {
    /// A source of exchange rates.
    nonisolated enum RateSource: String, Codable, CaseIterable, Sendable {
        case europeanCentralBank
        case coinbase

        var name: LocalizedStringResource {
            switch self {
            case .europeanCentralBank:
                LocalizedStringResource("European Central Bank", comment: "A source of exchange rates in Settings > Currency.")
            case .coinbase:
                LocalizedStringResource("Coinbase", comment: "A source of exchange rates in Settings > Currency.")
            }
        }
    }

    /// The source of exchange rates, or `nil` to show values in US dollars.
    var rateSource: RateSource?
    /// The ISO code of the chosen currency, or `nil` to follow the device's region.
    var currencyCode: String?

    /// Returns the ISO code of the currency that values show in.
    ///
    /// - Parameter locale: The locale whose region sets the automatic currency.
    /// - Returns: The currency's ISO code, or `nil` to keep the prices' own currency.
    func currency(in locale: Locale) -> String? {
        guard rateSource != nil else { return nil }
        return currencyCode ?? locale.currency?.identifier
    }
}
