import Foundation
@testable import RPC
import Testing
@testable import widgets

/// Checks how prices convert to the person's currency through the real price and exchange-rate adapters.
@MainActor
struct CurrencyPricesTests {
    /// Creates the prices under test around one test's fixtures.
    /// - Parameters:
    ///   - settings: The saved choice, if any.
    ///   - locale: The device's locale identifier.
    ///   - http: The fixture transport that every adapter shares.
    /// - Returns: Prices that convert Jupiter's quotes with the real rate adapters.
    private static func prices(_ settings: CurrencySettings?, locale: String = "en_US",
                               http: HTTPResponses) -> CurrencyPrices {
        CurrencyPrices(prices: Jupiter(transport: http), currency: .inMemory(StoredValue(settings), http: http),
                       locale: Locale(identifier: locale))
    }

    /// Dollar prices divide by the currency's rate, keeping their 24-hour change: SOL's $150 at $1.25 a euro is
    /// €120, and USDC's $1 is €0.80.
    /// - Parameter source: The rate source.
    @Test(arguments: CurrencySettings.RateSource.allCases)
    func `Quotes convert to the chosen currency`(source: CurrencySettings.RateSource) async throws {
        let http = HTTPResponses.currency()
        let prices = Self.prices(CurrencySettings(rateSource: source, currencyCode: "EUR"), http: http)

        let quotes = try await prices.prices(for: ["sol", "usdc"])

        #expect(quotes == ["sol": Quote(pricePerUnit: 120, currency: "EUR", dayChange: Decimal(string: "0.0129")),
                           "usdc": Quote(pricePerUnit: Decimal(string: "0.8")!, currency: "EUR", dayChange: nil)])
    }

    /// Without a rate source, or in the quotes' own currency, prices stay in dollars and no rate is read.
    /// - Parameter settings: The saved choice.
    @Test(arguments: [nil, CurrencySettings(currencyCode: "EUR"),
                      CurrencySettings(rateSource: .europeanCentralBank, currencyCode: "USD")] as [CurrencySettings?])
    func `Prices in dollars read no rates`(settings: CurrencySettings?) async throws {
        let http = HTTPResponses.currency()

        let quotes = try await Self.prices(settings, http: http).prices(for: ["sol"])

        #expect(quotes == ["sol": Quote(pricePerUnit: 150, currency: "USD", dayChange: Decimal(string: "0.0129"))])
        #expect(await http.requests.map { $0.url?.path() } == [CurrencyResponses.pricePath])
    }

    /// An automatic choice follows the region's currency: a German device shows euros.
    @Test func `An automatic choice follows the region's currency`() async throws {
        let http = HTTPResponses.currency()
        let prices = Self.prices(CurrencySettings(rateSource: .europeanCentralBank), locale: "de_DE", http: http)

        let quotes = try await prices.prices(for: ["usdc"])

        #expect(quotes == ["usdc": Quote(pricePerUnit: Decimal(string: "0.8")!, currency: "EUR", dayChange: nil)])
    }

    /// The bank doesn't publish Argentine pesos, so an automatic choice on an Argentine device keeps dollars, while a
    /// chosen peso leaves values unknown.
    /// - Parameters:
    ///   - code: The chosen currency, or `nil` to follow the region.
    ///   - expected: The quotes the lookup returns.
    @Test(arguments: [
        (nil, ["sol": Quote(pricePerUnit: 150, currency: "USD", dayChange: Decimal(string: "0.0129"))]),
        ("ARS", [:]),
    ] as [(String?, [String: Quote])])
    func `A currency without rates keeps dollars only when automatic`(code: String?,
                                                                      expected: [String: Quote]) async throws {
        let http = HTTPResponses.currency()
        let prices = Self.prices(CurrencySettings(rateSource: .europeanCentralBank, currencyCode: code),
                                 locale: "es_AR", http: http)

        #expect(try await prices.prices(for: ["sol"]) == expected)
    }

    /// A choice that can't be read fails the lookup instead of showing prices in another currency.
    @Test func `An unreadable choice fails the lookup`() async throws {
        let prices = CurrencyPrices(prices: Jupiter(transport: HTTPResponses.currency()),
                                    currency: .inMemory(StoredValue(failsLoading: true)))

        await #expect(throws: CurrencyError.settingsUnreadable) { try await prices.prices(for: ["sol"]) }
    }

    /// A rate limit fails the lookup instead of showing unconverted prices.
    @Test func `A rate failure fails the lookup`() async throws {
        let http = HTTPResponses.currency(error: .http(statusCode: 429, retryAfter: "60"),
                                          failingMethod: CurrencyResponses.referencePath)
        let prices = Self.prices(CurrencySettings(rateSource: .europeanCentralBank, currencyCode: "EUR"), http: http)

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: "60")) {
            try await prices.prices(for: ["sol"])
        }
    }
}
