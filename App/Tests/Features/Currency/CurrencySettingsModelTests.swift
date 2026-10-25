import Foundation
@testable import RPC
import Testing
@testable import widgets

/// Checks how the Currency screen reads the saved choice and runs each change.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CurrencySettingsModelTests {
    /// Creates the shared choice around one test's fixtures.
    /// - Parameters:
    ///   - settings: Storage for the choice.
    ///   - http: The fixture transport that the rate adapters share.
    /// - Returns: The selection.
    private static func selection(_ settings: StoredValue<CurrencySettings>,
                                  http: HTTPResponses = HTTPResponses([:], respond: CurrencyResponses.respond(to:)))
    -> CurrencySelection {
        CurrencySelection(settings: settings, rates: CurrencyResponses.rates(http), portfolios: { [] })
    }

    /// A read shows the saved choice.
    @Test func `A read shows the saved choice`() async {
        let saved = CurrencySettings(rateSource: .europeanCentralBank, currencyCode: "JPY")
        let model = CurrencySettingsModel()

        await model.reload(from: Self.selection(StoredValue(saved)))

        #expect(model.settings == saved)
    }

    /// An unreadable choice keeps nothing chosen and explains the read.
    @Test func `An unreadable choice explains why`() async {
        let model = CurrencySettingsModel()

        await model.reload(from: Self.selection(StoredValue(failsLoading: true)))

        #expect(model.settings == nil)
        #expect(model.error == .settingsUnreadable)
    }

    /// A tap saves its change once, ignoring taps while it waits, and the saved choice reaches every window.
    @Test func `A choice is saved once and reaches every window`() async {
        let settings = StoredValue<CurrencySettings>()
        let selection = Self.selection(settings)
        let model = CurrencySettingsModel()

        model.select(.coinbase)
        model.select(.europeanCentralBank)
        await model.run(model.attempt, with: selection)
        await model.reload(from: selection)

        #expect(await settings.value == CurrencySettings(rateSource: .coinbase))
        #expect(model.settings == CurrencySettings(rateSource: .coinbase))
        #expect(selection.revision.value == 1)
        #expect(model.attempt == nil)
    }

    /// A new source whose currencies can't load explains the rates, and a choice that can't be saved explains the
    /// save.
    /// - Parameters:
    ///   - source: The chosen rate source; Coinbase lists its currencies first, USD Only doesn't.
    ///   - failsSaving: Whether the choice can't be saved.
    ///   - error: The explained error.
    @Test(arguments: [
        (CurrencySettings.RateSource.coinbase, false, CurrencyError.ratesUnavailable),
        (nil, true, .settingsUnsaved),
    ] as [(CurrencySettings.RateSource?, Bool, CurrencyError)])
    func `A failed change explains why`(source: CurrencySettings.RateSource?, failsSaving: Bool,
                                        error: CurrencyError) async {
        let http = HTTPResponses([:], error: .transport(.notConnectedToInternet),
                                 failingMethod: CurrencyResponses.coinbasePath, respond: CurrencyResponses.respond(to:))
        let settings = StoredValue(CurrencySettings(rateSource: .europeanCentralBank, currencyCode: "JPY"),
                                   failsSaving: failsSaving)
        let model = CurrencySettingsModel()

        model.select(source)
        await model.run(model.attempt, with: Self.selection(settings, http: http))

        #expect(model.error == error)
    }
}
