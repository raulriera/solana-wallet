import Foundation
import Observation
import RPC
import Storage

/// The shared currency choice and each rate source's exchange rates.
@MainActor
@Observable
final class CurrencyStore: Erasable {
    private let choice: PersistentValue<CurrencySettings>
    private nonisolated let sources: [CurrencySettings.RateSource: any ExchangeRateProviding]

    /// Creates a store without reading the choice.
    ///
    /// - Parameters:
    ///   - storage: The storage that keeps the choice.
    ///   - rates: The exchange-rate provider for each rate source.
    init(storage: any ValueStoring<CurrencySettings>, rates: [CurrencySettings.RateSource: any ExchangeRateProviding]) {
        choice = PersistentValue(storage: storage, empty: CurrencySettings())
        sources = rates
    }

    /// Creates a store that keeps the choice in a directory, without reading it.
    ///
    /// - Parameters:
    ///   - directory: The directory that keeps the Currency files.
    ///   - rates: The exchange-rate provider for each rate source.
    convenience init(directory: URL, rates: [CurrencySettings.RateSource: any ExchangeRateProviding]) {
        let file = FileItem(url: directory.appending(path: "settings.json"), coding: .json(CurrencySettings.self))
        self.init(storage: file, rates: rates)
    }

    /// The currency choice, or `nil` until it's read.
    var settings: CurrencySettings? { phase == .loaded ? choice.value : nil }

    var phase: PersistentValuePhase { choice.phase }

    /// Loads the choice unless it's already loaded.
    func load() async {
        await choice.load()
    }

    /// Returns the choice, loading it first when needed.
    ///
    /// - Returns: The currency choice.
    /// - Throws: ``CurrencyError/settingsUnreadable`` when the choice can't be read.
    func loadedSettings() async throws -> CurrencySettings {
        try await choice.loadedValue(orThrow: CurrencyError.settingsUnreadable)
    }

    /// Looks up a rate source's exchange rates from a currency.
    ///
    /// - Parameters:
    ///   - currency: The ISO code of the currency to convert from.
    ///   - source: The rate source.
    /// - Returns: The amount of each currency that one unit of `currency` buys, keyed by ISO code.
    /// - Throws: An exchange-rate or cancellation error.
    nonisolated func rates(from currency: String, at source: CurrencySettings.RateSource) async throws
    -> [String: Decimal] {
        try await sources[source]?.rates(from: currency) ?? [:]
    }

    /// Lists the currencies that a rate source converts to.
    ///
    /// - Parameter source: The rate source.
    /// - Returns: The ISO codes of the source's currencies, in no particular order.
    /// - Throws: An exchange-rate or cancellation error.
    func currencies(for source: CurrencySettings.RateSource) async throws -> [String] {
        try await Array(rates(from: "USD", at: source).keys)
    }

    /// Saves a new rate source and clears a chosen currency that the source doesn't serve.
    ///
    /// - Parameter source: The rate source, or `nil` to show values in US dollars.
    /// - Throws: ``CurrencyError/settingsUnreadable`` when the choice can't be read, an exchange-rate error, or a
    ///   storage error.
    func select(_ source: CurrencySettings.RateSource?) async throws {
        let current = try await loadedSettings()
        let served: [String]? = if let source, source != current.rateSource, current.currencyCode != nil {
            try await currencies(for: source)
        } else {
            nil
        }
        try await choice.update {
            $0.rateSource = source
            if let code = $0.currencyCode, let served, !served.contains(code) { $0.currencyCode = nil }
        }
    }

    /// Saves a new currency.
    ///
    /// - Parameter code: The currency's ISO code, or `nil` to follow the device's region.
    /// - Throws: ``CurrencyError/settingsUnreadable`` when the choice can't be read, or a storage error.
    func select(currencyCode code: String?) async throws {
        _ = try await loadedSettings()
        try await choice.update { $0.currencyCode = code }
    }

    func erase() async throws {
        try await choice.forget()
    }
}
