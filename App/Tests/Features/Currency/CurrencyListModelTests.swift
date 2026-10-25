import Foundation
@testable import RPC
import Testing
@testable import widgets

/// Checks how the rate source's currencies load, narrow with a search, and name the automatic choice.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CurrencyListModelTests {
    /// Creates the shared choice around one test's fixtures.
    /// - Parameter http: The fixture transport that the rate adapters share.
    /// - Returns: The selection, which lists each source's currencies.
    private static func selection(_ http: HTTPResponses = HTTPResponses([:], respond: CurrencyResponses.respond(to:)))
    -> CurrencySelection {
        CurrencySelection(settings: StoredValue(), rates: CurrencyResponses.rates(http), portfolios: { [] })
    }

    /// A source's currencies load once; no source loads nothing.
    @Test func `A source's currencies load once`() async {
        let http = HTTPResponses([:], respond: CurrencyResponses.respond(to:))
        let selection = Self.selection(http)
        let model = CurrencyListModel()

        await model.load(nil, from: selection)
        #expect(model.currencies == nil)
        await model.load(.europeanCentralBank, from: selection)
        await model.load(.europeanCentralBank, from: selection)

        #expect(Set(model.currencies ?? []) == ["USD", "EUR", "JPY"])
        #expect(await http.requests.count == 1)
    }

    /// An automatic choice follows the region's currency, which the source is taken to serve until its currencies load,
    /// and US dollars once they show it doesn't.
    /// - Parameters:
    ///   - locale: The device's locale identifier.
    ///   - region: The region's currency.
    ///   - currency: The currency that values show in once the currencies load.
    @Test(arguments: [("de_DE", "EUR", "EUR"), ("ja_JP", "JPY", "JPY"), ("es_AR", "ARS", "USD")])
    func `An automatic choice follows the region where the source serves it`(locale: String, region: String,
                                                                            currency: String) async {
        let model = CurrencyListModel(locale: Locale(identifier: locale))
        #expect(model.automaticCurrency == region)

        await model.load(.europeanCentralBank, from: Self.selection())

        #expect(model.automaticCurrency == currency)
    }

    /// Currencies are ordered by name, and a search matches a name or a code.
    /// - Parameters:
    ///   - search: The search text.
    ///   - codes: The matching currencies, in order.
    @Test(arguments: [("", ["EUR", "JPY", "USD"]), ("yen", ["JPY"]), ("usd", ["USD"]), ("peso", [])])
    func `Currencies are ordered by name and searchable`(search: String, codes: [String]) async {
        let model = CurrencyListModel(locale: Locale(identifier: "en_US"))
        await model.load(.europeanCentralBank, from: Self.selection())

        model.search = search

        #expect(model.listed == codes)
    }

    /// Currencies that can't load show why until a retry, which clears the error and counts the retry.
    @Test func `Currencies that can't load can be loaded again`() async {
        let http = HTTPResponses([:], error: .transport(.notConnectedToInternet),
                                 failingMethod: CurrencyResponses.coinbasePath, respond: CurrencyResponses.respond(to:))
        let model = CurrencyListModel()
        await model.load(.coinbase, from: Self.selection(http))
        #expect(model.error == .ratesUnavailable)
        #expect(model.currencies == nil)

        model.retryLoading()

        #expect(model.error == nil)
        #expect(model.retry == 1)
    }

    /// Another source keeps the previous source's currencies on screen until its own load, so nothing flashes.
    @Test func `Another source's currencies replace the previous ones once they load`() async {
        let http = HTTPResponses([:], respond: CurrencyResponses.respond(to:))
        let selection = Self.selection(http)
        let model = CurrencyListModel()
        await model.load(.europeanCentralBank, from: selection)

        await model.load(.coinbase, from: selection)

        #expect(model.currencies != nil)
        #expect(await http.requests.map { $0.url?.path() } == [CurrencyResponses.referencePath,
                                                               CurrencyResponses.coinbasePath])
    }
}
