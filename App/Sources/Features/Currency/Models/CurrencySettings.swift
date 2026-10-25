import Foundation

/// The currency that every window shows values in and the exchange rates that convert them, saved on this device.
nonisolated struct CurrencySettings: Codable, Equatable, Sendable {
    /// A source of exchange rates.
    nonisolated enum RateSource: String, Codable, CaseIterable, Sendable {
        /// The European Central Bank's daily reference rates.
        case europeanCentralBank
        /// Coinbase's rates, updated through the day.
        case coinbase

        /// The source's name as people see it.
        var name: LocalizedStringResource {
            switch self {
            case .europeanCentralBank:
                LocalizedStringResource("European Central Bank", comment: "A source of exchange rates in Settings > Currency.")
            case .coinbase:
                LocalizedStringResource("Coinbase", comment: "A source of exchange rates in Settings > Currency.")
            }
        }
    }

    /// Where exchange rates come from, or `nil` to show values in US dollars, as the prices come, without rates.
    var rateSource: RateSource?
    /// The ISO code of the chosen currency, or `nil` to follow the device's region.
    var currencyCode: String?

    /// The ISO code of the currency that values show in, or `nil` to keep the prices' own currency.
    /// - Parameter locale: The locale whose region's currency an automatic choice follows.
    /// - Returns: The chosen currency, or the region's when none is chosen; `nil` without a rate source or a
    ///   currency for the region.
    func currency(in locale: Locale) -> String? {
        guard rateSource != nil else { return nil }
        return currencyCode ?? locale.currency?.identifier
    }
}
