import Foundation
import Observation
import RPC
import Storage

/// The currency and rate source choice that every window shares, so a change in one window shows in the others and
/// applies to prices at once, with the exchange rates that each rate source supplies.
///
/// The store reads nothing until ``load()``. Each change shows at once and saves after the changes made before it; a
/// change that can't be saved is undone and throws. Choosing what's already chosen saves nothing. Erasing returns the
/// store to how it starts, with nothing read.
@MainActor
@Observable
final class CurrencyStore: Erasable {
    private let choice: PersistentValue<CurrencySettings>
    private nonisolated let sources: [CurrencySettings.RateSource: any ExchangeRateProviding]
    /// Whether the choice was erased since it was last read, so it shows as not read until the next read.
    private var isErased = false

    /// Connects to the storage that keeps the choice, without reading it.
    /// - Parameters:
    ///   - storage: The storage that keeps the choice.
    ///   - rates: The exchange-rate provider for each rate source; a source without one has no rates.
    init(storage: any ValueStoring<CurrencySettings>, rates: [CurrencySettings.RateSource: any ExchangeRateProviding]) {
        choice = PersistentValue(storage: storage, empty: CurrencySettings())
        sources = rates
    }

    /// Connects to the choice's file in a directory, without reading it.
    /// - Parameters:
    ///   - directory: The directory that keeps the Currency files.
    ///   - rates: The exchange-rate provider for each rate source; a source without one has no rates.
    convenience init(directory: URL, rates: [CurrencySettings.RateSource: any ExchangeRateProviding]) {
        let file = FileItem(url: directory.appending(path: "settings.json"), coding: .json(CurrencySettings.self))
        self.init(storage: file, rates: rates)
    }

    /// The choice with every change made so far, or `nil` until it's read, so nothing shows as chosen; before
    /// anything is saved, it's US dollars without rates.
    var settings: CurrencySettings? { phase == .loaded ? choice.value : nil }

    /// Whether the choice was read since the store started or was erased.
    var phase: PersistentValuePhase { isErased ? .unloaded : choice.phase }

    /// Reads the choice, unless it was already read, and returns once the changes made before this call are saved or
    /// undone.
    func load() async {
        await choice.load()
        isErased = false
    }

    /// Reads the choice, unless it was already read, and returns it with every change made so far, without waiting
    /// for those changes to save.
    /// - Returns: The choice that prices convert with.
    /// - Throws: ``CurrencyError/settingsUnreadable`` when the choice can't be read.
    func loadedSettings() async throws -> CurrencySettings {
        if settings == nil { await load() }
        guard let settings else { throw CurrencyError.settingsUnreadable }
        return settings
    }

    /// Looks up a rate source's exchange rates from a currency.
    /// - Parameters:
    ///   - currency: The ISO code of the currency to convert from.
    ///   - source: The rate source.
    /// - Returns: How much of each currency that the source serves one unit of `currency` buys; none for a source
    ///   without rates.
    /// - Throws: An exchange-rate or cancellation error.
    nonisolated func rates(from currency: String, at source: CurrencySettings.RateSource) async throws
    -> [String: Decimal] {
        try await sources[source]?.rates(from: currency) ?? [:]
    }

    /// Lists the currencies that a rate source converts to.
    /// - Parameter source: The rate source.
    /// - Returns: The ISO codes of the source's currencies, including US dollars, in no particular order.
    /// - Throws: An exchange-rate or cancellation error.
    func currencies(for source: CurrencySettings.RateSource) async throws -> [String] {
        // Prices come in US dollars, so the source's rates from the dollar name every currency it converts to.
        try await Array(rates(from: "USD", at: source).keys)
    }

    /// Saves a new rate source; a chosen currency that the new source doesn't serve goes back to the region's.
    ///
    /// The choice is read first if it wasn't yet, so the chosen currency is known.
    /// - Parameter source: The rate source, or `nil` to show values in US dollars.
    /// - Throws: ``CurrencyError/settingsUnreadable`` when the choice can't be read, an exchange-rate error when the
    ///   new source's currencies can't be listed, or a storage error after undoing the change.
    func select(_ source: CurrencySettings.RateSource?) async throws {
        let current = try await loadedSettings()
        // Only another source with a chosen currency needs to list what it serves.
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
    /// The choice is read first if it wasn't yet, so the change shows and every observer hears of it.
    /// - Parameter code: The ISO code of the currency, or `nil` to follow the device's region.
    /// - Throws: ``CurrencyError/settingsUnreadable`` when the choice can't be read, or a storage error after undoing
    ///   the change.
    func select(currencyCode code: String?) async throws {
        _ = try await loadedSettings()
        try await choice.update { $0.currencyCode = code }
    }

    /// Deletes the saved choice after the changes made before it, and shows it as not read until the next read, which
    /// finds US dollars.
    ///
    /// A reset erases the choice, so nothing that observes it, such as prices, takes the erasure for a new choice.
    /// - Throws: A storage error, which keeps the choice.
    func erase() async throws {
        // Not read from the start, so observers never see the emptied choice as a change.
        isErased = true
        do {
            try await choice.erase()
        } catch {
            isErased = false
            throw error
        }
    }
}
