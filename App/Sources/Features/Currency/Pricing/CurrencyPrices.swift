import Foundation
import RPC

/// A price provider that converts another provider's quotes to the chosen currency.
nonisolated struct CurrencyPrices: PriceProviding {
    private let prices: any PriceProviding
    private let currency: CurrencyStore
    private let locale: Locale

    var network: Network { prices.network }

    /// Creates a price provider that converts another provider's quotes.
    ///
    /// - Parameters:
    ///   - prices: The provider of the quotes to convert.
    ///   - currency: The currency store.
    ///   - locale: The locale whose region sets the automatic currency.
    init(prices: any PriceProviding, currency: CurrencyStore, locale: Locale = .autoupdatingCurrent) {
        self.prices = prices
        self.currency = currency
        self.locale = locale
    }

    @concurrent
    func response(for mints: [String]) async throws -> Conversion {
        async let chosen = currency.loadedSettings()
        async let looked = prices.prices(for: mints)
        let (choice, quotes) = try await (chosen, looked)
        guard let source = choice.rateSource, let target = choice.currency(in: locale),
              quotes.values.contains(where: { $0.currency != target }) else { return Conversion(quotes: quotes, target: nil) }
        let rates = try await currency.rates(from: target, at: source)
        let keepsQuotes = rates.isEmpty && choice.currencyCode == nil
        return Conversion(quotes: quotes, target: keepsQuotes ? nil : (target, rates))
    }

    func quotes(from response: Conversion) throws -> [String: Quote] {
        guard let (target, rates) = response.target else { return response.quotes }
        return response.quotes.compactMapValues { quote in
            if quote.currency == target { return quote }
            guard let rate = rates[quote.currency], rate > 0 else { return nil }
            return Quote(pricePerUnit: quote.pricePerUnit / rate, currency: target, dayChange: quote.dayChange)
        }
    }

    /// Quotes and the exchange rates that convert them.
    nonisolated struct Conversion: Sendable {
        let quotes: [String: Quote]
        /// The ISO code of the currency to convert to and how much of each currency one unit of it buys, or `nil` to
        /// keep the quotes' own currencies.
        let target: (currency: String, rates: [String: Decimal])?
    }
}
