import Foundation
import Observation

/// Loads and searches the rate source's currencies.
@MainActor
@Observable
final class CurrencyListModel {
    /// The ISO codes of the rate source's currencies, or `nil` until they load.
    private(set) var currencies: [String]? {
        didSet {
            updateListed()
            automaticCurrency = Self.automaticCurrency(in: locale, from: currencies)
        }
    }
    /// The ISO code of the currency that an automatic choice uses.
    private(set) var automaticCurrency: String
    var search = "" {
        didSet { updateListed() }
    }
    /// The currencies that match ``search``, ordered by name.
    private(set) var listed: [String] = []
    private(set) var error: CurrencyError?
    /// The number of retries after a failure.
    private(set) var retry = 0
    /// The rate source of ``currencies``.
    @ObservationIgnored private var source: CurrencySettings.RateSource?
    private let locale: Locale

    /// Creates a model without currencies.
    ///
    /// - Parameter locale: The locale that names and orders the currencies and sets the automatic currency.
    init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
        automaticCurrency = Self.automaticCurrency(in: locale, from: nil)
    }

    /// Returns the ISO code of the currency that an automatic choice uses.
    ///
    /// - Parameters:
    ///   - locale: The locale whose region sets the currency.
    ///   - currencies: The ISO codes that the rate source serves, or `nil` until they load.
    /// - Returns: The region's currency, or `USD` when the region has none or the source doesn't serve it.
    private static func automaticCurrency(in locale: Locale, from currencies: [String]?) -> String {
        guard let region = locale.currency?.identifier, currencies?.contains(region) ?? true else { return "USD" }
        return region
    }

    /// Loads a rate source's currencies unless they're already loaded.
    ///
    /// - Parameters:
    ///   - source: The chosen rate source, or `nil` when none is chosen.
    ///   - store: The currency store.
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

    /// Loads the currencies again after a failure.
    func retryLoading() {
        error = nil
        retry += 1
    }

    /// Lists the currencies whose name or code contains the search, ordered by name.
    private func updateListed() {
        let style = CurrencyNameFormatStyle(locale: locale)
        let named = (currencies ?? []).map { (code: $0, name: style.format($0)) }
        listed = named
            .filter { search.isEmpty || $0.name.localizedStandardContains(search) || $0.code.localizedStandardContains(search) }
            .sorted { $0.name.compare($1.name, locale: locale) == .orderedAscending }
            .map(\.code)
    }
}
