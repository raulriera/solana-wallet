import Foundation
@testable import RPC
import Testing
@testable import widgets

@MainActor
struct CurrencyPriceProviderTests {
    private static func prices(_ settings: CurrencySettings?, locale: String = "en_US",
                               http: HTTPResponses) -> CurrencyPriceProvider {
        CurrencyPriceProvider(prices: JupiterPriceProvider(transport: http),
                              currency: .inMemory(StoredValue(settings), http: http), locale: Locale(identifier: locale))
    }

    @Test(arguments: CurrencySettings.RateSource.allCases)
    func `Quotes convert to the chosen currency`(source: CurrencySettings.RateSource) async throws {
        let http = HTTPResponses.currency()
        let prices = Self.prices(CurrencySettings(rateSource: source, currencyCode: "EUR"), http: http)

        let quotes = try await prices.prices(for: ["sol", "usdc"])

        #expect(quotes == ["sol": Quote(pricePerUnit: 120, currency: "EUR", dayChange: Decimal(string: "0.0129")),
                           "usdc": Quote(pricePerUnit: Decimal(string: "0.8")!, currency: "EUR", dayChange: nil)])
    }

    @Test(arguments: [nil, CurrencySettings(currencyCode: "EUR"),
                      CurrencySettings(rateSource: .europeanCentralBank, currencyCode: "USD")] as [CurrencySettings?])
    func `Prices in dollars read no rates`(settings: CurrencySettings?) async throws {
        let http = HTTPResponses.currency()

        let quotes = try await Self.prices(settings, http: http).prices(for: ["sol"])

        #expect(quotes == ["sol": Quote(pricePerUnit: 150, currency: "USD", dayChange: Decimal(string: "0.0129"))])
        #expect(await http.requests.map { $0.url?.path() } == [CurrencyResponses.pricePath])
    }

    @Test func `An automatic choice follows the region's currency`() async throws {
        let http = HTTPResponses.currency()
        let prices = Self.prices(CurrencySettings(rateSource: .europeanCentralBank), locale: "de_DE", http: http)

        let quotes = try await prices.prices(for: ["usdc"])

        #expect(quotes == ["usdc": Quote(pricePerUnit: Decimal(string: "0.8")!, currency: "EUR", dayChange: nil)])
    }

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

    @Test func `An unreadable choice fails the lookup`() async throws {
        let prices = CurrencyPriceProvider(prices: JupiterPriceProvider(transport: HTTPResponses.currency()),
                                           currency: .inMemory(StoredValue(failsLoading: true)))

        await #expect(throws: CurrencyError.settingsUnreadable) { try await prices.prices(for: ["sol"]) }
    }

    @Test func `A rate failure fails the lookup`() async throws {
        let http = HTTPResponses.currency(error: .http(statusCode: 429, retryAfter: "60"),
                                          failingMethod: CurrencyResponses.referencePath)
        let prices = Self.prices(CurrencySettings(rateSource: .europeanCentralBank, currencyCode: "EUR"), http: http)

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: "60")) {
            try await prices.prices(for: ["sol"])
        }
    }
}
