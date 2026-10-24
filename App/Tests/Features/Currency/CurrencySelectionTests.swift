import Foundation
import Testing
@testable import widgets

/// Checks that currency choices are saved before every created portfolio reads its prices again.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CurrencySelectionTests {
    /// A new rate source and a new currency are each saved, and each portfolio reads its prices again after each.
    @Test func `A new choice is saved and every portfolio reads prices again`() async throws {
        let settings = StoredValue<CurrencySettings>()
        let mainnet = PortfolioChanges()
        let devnet = PortfolioChanges()
        let selection = CurrencySelection(settings: settings, portfolios: { [mainnet, devnet] })

        try await selection.select(.coinbase)
        try await selection.select(currencyCode: "EUR")

        #expect(await settings.value == CurrencySettings(rateSource: .coinbase, currencyCode: "EUR"))
        #expect(try await selection.settings() == CurrencySettings(rateSource: .coinbase, currencyCode: "EUR"))
        #expect(await mainnet.priceChanges == 2)
        #expect(await devnet.priceChanges == 2)
    }

    /// Choosing what's already saved, including the defaults before anything is saved, saves nothing and reads no
    /// prices.
    /// - Parameter saved: The choice saved before the test, if any.
    @Test(arguments: [nil, CurrencySettings(rateSource: .europeanCentralBank)] as [CurrencySettings?])
    func `An unchanged choice reads no prices`(saved: CurrencySettings?) async throws {
        let settings = StoredValue(saved)
        let portfolio = PortfolioChanges()
        let selection = CurrencySelection(settings: settings, portfolios: { [portfolio] })

        try await selection.select(saved?.rateSource)

        #expect(await settings.value == saved)
        #expect(await portfolio.priceChanges == 0)
    }

    /// A choice that can't be saved changes nothing, so no portfolio reads prices again.
    @Test func `A failed save reads no prices`() async throws {
        let settings = StoredValue<CurrencySettings>(failsSaving: true)
        let portfolio = PortfolioChanges()
        let selection = CurrencySelection(settings: settings, portfolios: { [portfolio] })

        await #expect(throws: CocoaError(.fileWriteUnknown)) { try await selection.select(.coinbase) }

        #expect(await settings.value == nil)
        #expect(await portfolio.priceChanges == 0)
    }
}
