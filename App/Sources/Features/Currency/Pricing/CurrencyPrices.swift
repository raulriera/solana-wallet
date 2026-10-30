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
    func prices(for mints: [String]) async throws -> [String: Quote] {
        async let chosen = currency.loadedSettings()
        async let looked = prices.prices(for: mints)
        let (choice, quotes) = try await (chosen, looked)
        guard let source = choice.rateSource, let target = choice.currency(in: locale),
              quotes.values.contains(where: { $0.currency != target }) else { return quotes }
        let rates = try await currency.rates(from: target, at: source)
        if rates.isEmpty, choice.currencyCode == nil { return quotes }
        return quotes.compactMapValues { quote in
            if quote.currency == target { return quote }
            guard let rate = rates[quote.currency], rate > 0 else { return nil }
            return Quote(pricePerUnit: quote.pricePerUnit / rate, currency: target, dayChange: quote.dayChange)
        }
    }
}
