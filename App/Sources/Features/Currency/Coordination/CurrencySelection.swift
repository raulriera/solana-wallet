import Foundation
import Portfolio

/// Saves the currency and rate source choice and has each created portfolio read its prices again.
@MainActor
struct CurrencySelection {
    private let store: any ValueStoring<CurrencySettings>
    private let portfolios: @MainActor @Sendable () -> [any PortfolioProviding]

    /// Connects the choice to the storage and portfolios it changes.
    /// - Parameters:
    ///   - settings: Device storage for the currency and rate source choice.
    ///   - portfolios: Returns the portfolios created so far, whose prices read the choice before every lookup.
    init(settings: any ValueStoring<CurrencySettings>,
         portfolios: @escaping @MainActor @Sendable () -> [any PortfolioProviding]) {
        store = settings
        self.portfolios = portfolios
    }

    /// Reads the saved choice.
    /// - Returns: The saved settings, or US dollars without rates before anything is saved.
    /// - Throws: A storage or cancellation error.
    func settings() async throws -> CurrencySettings {
        try await store.load() ?? CurrencySettings()
    }

    /// Saves a new rate source.
    /// - Parameter source: The rate source, or `nil` to show values in US dollars.
    /// - Throws: A storage or cancellation error, which changes nothing.
    func select(_ source: CurrencySettings.RateSource?) async throws {
        try await apply { $0.rateSource = source }
    }

    /// Saves a new currency.
    /// - Parameter code: The ISO code of the currency, or `nil` to follow the device's region.
    /// - Throws: A storage or cancellation error, which changes nothing.
    func select(currencyCode code: String?) async throws {
        try await apply { $0.currencyCode = code }
    }

    /// Saves a change in one storage step, so changes from several windows don't overwrite each other, then has each
    /// portfolio read its prices again.
    ///
    /// Unchanged settings aren't saved and read no prices.
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
    }
}
