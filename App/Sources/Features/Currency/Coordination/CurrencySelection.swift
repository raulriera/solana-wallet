import Foundation
import Portfolio
import RPC

/// Saves the currency and rate source choice, lists each source's currencies, and has each created portfolio read its
/// prices again after a change.
///
/// Every window shares one selection, which reaches Currency's screens through the environment.
@MainActor
final class CurrencySelection {
    /// Advances after every saved change, so each window's Currency screen reads the choice again.
    let revision = Revision()
    private let store: any ValueStoring<CurrencySettings>
    private let rates: [CurrencySettings.RateSource: any ExchangeRateProviding]
    private let portfolios: @MainActor @Sendable () -> [any PortfolioProviding]

    /// Connects the choice to the storage, rate sources, and portfolios it changes.
    /// - Parameters:
    ///   - settings: Device storage for the currency and rate source choice.
    ///   - rates: The exchange-rate provider for each rate source, which the portfolios' prices share.
    ///   - portfolios: Returns the portfolios created so far, whose prices read the choice before every lookup.
    init(settings: any ValueStoring<CurrencySettings>, rates: [CurrencySettings.RateSource: any ExchangeRateProviding],
         portfolios: @escaping @MainActor @Sendable () -> [any PortfolioProviding]) {
        store = settings
        self.rates = rates
        self.portfolios = portfolios
    }

    /// Reads the saved choice.
    /// - Returns: The saved settings, or US dollars without rates before anything is saved.
    /// - Throws: A storage or cancellation error.
    func settings() async throws -> CurrencySettings {
        try await store.load() ?? CurrencySettings()
    }

    /// Lists the currencies that a rate source converts to.
    /// - Parameter source: The rate source.
    /// - Returns: The ISO codes of the source's currencies, including US dollars, in no particular order.
    /// - Throws: An exchange-rate or cancellation error.
    func currencies(for source: CurrencySettings.RateSource) async throws -> [String] {
        guard let provider = rates[source] else { return [] }
        // Prices come in US dollars, so the source's rates from the dollar name every currency it converts to.
        return try await Array(provider.rates(from: "USD").keys)
    }

    /// Saves a new rate source; a chosen currency that the new source doesn't serve goes back to the region's.
    /// - Parameter source: The rate source, or `nil` to show values in US dollars.
    /// - Throws: An exchange-rate error when the new source's currencies can't be listed, or a storage or
    ///   cancellation error; each changes nothing.
    func select(_ source: CurrencySettings.RateSource?) async throws {
        var code = try await settings().currencyCode
        if let chosen = code, let source, try await !currencies(for: source).contains(chosen) { code = nil }
        try await apply { [code] in
            $0.rateSource = source
            $0.currencyCode = code
        }
    }

    /// Saves a new currency.
    /// - Parameter code: The ISO code of the currency, or `nil` to follow the device's region.
    /// - Throws: A storage or cancellation error, which changes nothing.
    func select(currencyCode code: String?) async throws {
        try await apply { $0.currencyCode = code }
    }

    /// Saves a change in one storage step, so changes from several windows don't overwrite each other, then has each
    /// portfolio read its prices again and tells every window.
    ///
    /// Unchanged settings aren't saved, read no prices, and tell no window.
    /// - Parameter change: Changes the settings, which start from the defaults before anything is saved.
    /// - Throws: A storage or cancellation error, which changes nothing.
    private func apply(_ change: @escaping @Sendable (inout CurrencySettings) -> Void) async throws {
        let changed = try await store.update { saved in
            let old = saved ?? CurrencySettings()
            var new = old
            change(&new)
            // Unchanged defaults stay unsaved.
            if new != old { saved = new }
            return new != old
        }
        guard changed else { return }
        // Each network's portfolio reads its prices again on its own.
        await withDiscardingTaskGroup { group in
            for portfolio in portfolios() { group.addTask { await portfolio.pricesDidChange() } }
        }
        revision.advance()
    }
}
