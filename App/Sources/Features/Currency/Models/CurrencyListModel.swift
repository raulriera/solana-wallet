import Foundation
import Observation

/// Owns the rate source's currencies: loading them, the search that narrows them, and the currency that an automatic
/// choice follows.
@MainActor
@Observable
final class CurrencyListModel {
    /// The ISO codes of the rate source's currencies, or `nil` until they load.
    private(set) var currencies: [String]? {
        didSet { updateListed() }
    }
    /// The text that narrows the listed currencies to those whose name or code contains it.
    var search = "" {
        didSet { updateListed() }
    }
    /// The currencies that match ``search``, ordered by name.
    private(set) var listed: [String] = []
    /// Why the currencies couldn't load, until a retry.
    private(set) var error: CurrencyError?
    /// Counts retries after a failure, so each one loads the currencies again.
    private(set) var retry = 0
    /// The rate source that ``currencies`` belong to.
    @ObservationIgnored private var source: CurrencySettings.RateSource?
    private let locale: Locale

    /// Starts without currencies.
    /// - Parameter locale: The locale whose region's currency an automatic choice follows, and that names and orders the
    ///   currencies, as the prices' conversion does.
    init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    /// The currency that an automatic choice shows values in: the region's when the rate source serves it, which it
    /// is taken to do until its currencies load, and US dollars otherwise.
    var automaticCurrency: String {
        guard let region = locale.currency?.identifier, currencies?.contains(region) ?? true else { return "USD" }
        return region
    }

    /// Loads a rate source's currencies, unless they're already loaded.
    ///
    /// Another source's currencies stay until these load, so what they show doesn't flash.
    /// - Parameters:
    ///   - source: The chosen rate source, or `nil` when none is chosen and nothing loads.
    ///   - store: The choice that every window shares, which lists each source's currencies.
    func load(_ source: CurrencySettings.RateSource?, from store: CurrencyStore) async {
        guard let source, currencies == nil || self.source != source else { return }
        error = nil
        do {
            let codes = try await store.currencies(for: source)
            guard !Task.isCancelled else { return }
            currencies = codes
            self.source = source
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .ratesUnavailable
        }
    }

    /// Loads the currencies again after they failed.
    func retryLoading() {
        error = nil
        retry += 1
    }

    /// Lists the currencies whose name or code contains the search, ordered by name.
    private func updateListed() {
        let named = (currencies ?? []).map { (code: $0, name: locale.localizedString(forCurrencyCode: $0) ?? $0) }
        listed = named
            .filter { search.isEmpty || $0.name.localizedStandardContains(search) || $0.code.localizedStandardContains(search) }
            .sorted { $0.name.compare($1.name, locale: locale) == .orderedAscending }
            .map(\.code)
    }
}
