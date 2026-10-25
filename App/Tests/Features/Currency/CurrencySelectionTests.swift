import Foundation
@testable import RPC
import Testing
@testable import widgets

/// Checks that currency choices are saved before every created portfolio reads its prices again and every window
/// hears about them, and that a new rate source keeps only a currency it serves.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CurrencySelectionTests {
    /// Creates the selection under test around one test's fixtures.
    /// - Parameters:
    ///   - settings: Storage for the choice.
    ///   - http: The fixture transport that the rate adapters share.
    ///   - portfolios: The portfolios created so far.
    /// - Returns: The selection.
    private static func selection(_ settings: StoredValue<CurrencySettings>,
                                  http: HTTPResponses = HTTPResponses([:], respond: CurrencyResponses.respond(to:)),
                                  portfolios: [PortfolioChanges] = []) -> CurrencySelection {
        CurrencySelection(settings: settings, rates: CurrencyResponses.rates(http), portfolios: { portfolios })
    }

    /// A new rate source and a new currency are each saved, and after each, every portfolio reads its prices again and
    /// every window hears about it.
    @Test func `A new choice is saved and every portfolio reads prices again`() async throws {
        let settings = StoredValue<CurrencySettings>()
        let mainnet = PortfolioChanges()
        let devnet = PortfolioChanges()
        let selection = Self.selection(settings, portfolios: [mainnet, devnet])

        try await selection.select(.coinbase)
        try await selection.select(currencyCode: "EUR")

        #expect(await settings.value == CurrencySettings(rateSource: .coinbase, currencyCode: "EUR"))
        #expect(try await selection.settings() == CurrencySettings(rateSource: .coinbase, currencyCode: "EUR"))
        #expect(await mainnet.priceChanges == 2)
        #expect(await devnet.priceChanges == 2)
        #expect(selection.revision.value == 2)
    }

    /// Choosing what's already saved, including the defaults before anything is saved, saves nothing, reads no
    /// prices, and tells no window.
    /// - Parameter saved: The choice saved before the test, if any.
    @Test(arguments: [nil, CurrencySettings(rateSource: .europeanCentralBank)] as [CurrencySettings?])
    func `An unchanged choice reads no prices`(saved: CurrencySettings?) async throws {
        let settings = StoredValue(saved)
        let portfolio = PortfolioChanges()
        let selection = Self.selection(settings, portfolios: [portfolio])

        try await selection.select(saved?.rateSource)

        #expect(await settings.value == saved)
        #expect(await portfolio.priceChanges == 0)
        #expect(selection.revision.value == 0)
    }

    /// A choice that can't be saved changes nothing, so no portfolio reads prices again.
    @Test func `A failed save reads no prices`() async throws {
        let settings = StoredValue<CurrencySettings>(failsSaving: true)
        let portfolio = PortfolioChanges()
        let selection = Self.selection(settings, portfolios: [portfolio])

        await #expect(throws: CocoaError(.fileWriteUnknown)) { try await selection.select(.coinbase) }

        #expect(await settings.value == nil)
        #expect(await portfolio.priceChanges == 0)
        #expect(selection.revision.value == 0)
    }

    /// A new source keeps a chosen currency that it serves, the yen, and goes back to the region's for one it doesn't,
    /// the Argentine peso; USD Only keeps the choice for later.
    /// - Parameters:
    ///   - chosen: The currency chosen before the switch.
    ///   - source: The new rate source.
    ///   - kept: The currency chosen after the switch.
    @Test(arguments: [
        ("JPY", .europeanCentralBank, "JPY"),
        ("ARS", .europeanCentralBank, nil),
        ("ARS", nil, "ARS"),
    ] as [(String, CurrencySettings.RateSource?, String?)])
    func `A new source keeps only a currency it serves`(chosen: String, source: CurrencySettings.RateSource?,
                                                       kept: String?) async throws {
        let settings = StoredValue(CurrencySettings(rateSource: .coinbase, currencyCode: chosen))

        try await Self.selection(settings).select(source)

        #expect(await settings.value == CurrencySettings(rateSource: source, currencyCode: kept))
    }

    /// When the new source's currencies can't be listed, nothing changes.
    @Test func `A source whose currencies can't load changes nothing`() async throws {
        let saved = CurrencySettings(rateSource: .coinbase, currencyCode: "JPY")
        let settings = StoredValue(saved)
        let http = HTTPResponses([:], error: .http(statusCode: 429, retryAfter: nil),
                                 failingMethod: CurrencyResponses.referencePath, respond: CurrencyResponses.respond(to:))

        await #expect(throws: RPCError.http(statusCode: 429, retryAfter: nil)) {
            try await Self.selection(settings, http: http).select(.europeanCentralBank)
        }

        #expect(await settings.value == saved)
    }

    /// Each source lists the currencies it converts to, including US dollars.
    /// - Parameter source: The rate source.
    @Test(arguments: CurrencySettings.RateSource.allCases)
    func `A source lists its currencies`(source: CurrencySettings.RateSource) async throws {
        let currencies = try await Self.selection(StoredValue()).currencies(for: source)

        #expect(Set(currencies) == ["USD", "EUR", "JPY"])
    }
}
