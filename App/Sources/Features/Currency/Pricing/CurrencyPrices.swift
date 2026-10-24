import Foundation
import RPC

/// Supplies prices in the person's currency: another provider's quotes, converted with the chosen exchange rates.
///
/// Each lookup reads the saved choice, so a change made in any window applies to the next lookup. Without a rate
/// source, or when the quotes are already in the person's currency, quotes pass through without a rate request.
/// A quote in a currency without a rate has no price, which leaves its value unknown. When the device's region has a
/// currency that the rate source doesn't serve, an automatic choice keeps the quotes' own currency.
nonisolated struct CurrencyPrices: PriceProviding {
    private let prices: any PriceProviding
    private let settings: any ValueStoring<CurrencySettings>
    private let rates: [CurrencySettings.RateSource: any ExchangeRateProviding]
    private let locale: Locale

    /// The network whose mint addresses the converted quotes identify.
    var network: Network { prices.network }

    /// Converts another provider's quotes with the exchange rates that the saved choice names.
    /// - Parameters:
    ///   - prices: The provider of the quotes to convert.
    ///   - settings: Device storage for the currency and rate source choice.
    ///   - rates: The exchange-rate provider for each rate source; a source without one has no rates.
    ///   - locale: The locale whose region's currency an automatic choice follows.
    init(prices: any PriceProviding, settings: any ValueStoring<CurrencySettings>,
         rates: [CurrencySettings.RateSource: any ExchangeRateProviding] = [.europeanCentralBank: EuropeanCentralBank(),
                                                                            .coinbase: Coinbase()],
         locale: Locale = .autoupdatingCurrent) {
        self.prices = prices
        self.settings = settings
        self.rates = rates
        self.locale = locale
    }

    /// Looks up quotes, then converts those in another currency to the person's currency.
    ///
    /// The choice is read while the quotes are looked up. Rates are looked up after the quotes, because only quotes in
    /// another currency need them.
    /// - Parameter mints: Mint addresses on this provider's network; duplicates are ignored.
    /// - Returns: Quotes in the person's currency, keyed by mint; a quote without a rate is left out.
    /// - Throws: A storage, price, exchange-rate, or cancellation error.
    @concurrent
    func prices(for mints: [String]) async throws -> [String: Quote] {
        async let saved = settings.load()
        async let looked = prices.prices(for: mints)
        let (choice, quotes) = try await (saved ?? CurrencySettings(), looked)
        guard let source = choice.rateSource, let currency = choice.currency(in: locale),
              quotes.values.contains(where: { $0.currency != currency }) else { return quotes }
        let rates = try await self.rates[source]?.rates(from: currency) ?? [:]
        // The region's currency isn't served, so an automatic choice shows the prices as they come.
        if rates.isEmpty, choice.currencyCode == nil { return quotes }
        return quotes.compactMapValues { quote in
            if quote.currency == currency { return quote }
            // A rate counts the quote's currency in one unit of the person's currency.
            guard let rate = rates[quote.currency], rate > 0 else { return nil }
            return Quote(pricePerUnit: quote.pricePerUnit / rate, currency: currency, dayChange: quote.dayChange)
        }
    }
}
