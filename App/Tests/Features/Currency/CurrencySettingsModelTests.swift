import Foundation
@testable import RPC
import Testing
@testable import widgets

/// Checks how the Currency screens read the shared choice and run each change.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CurrencySettingsModelTests {
    /// A read explains only a choice that can't be read.
    /// - Parameters:
    ///   - failsLoading: Whether the choice can't be read.
    ///   - error: The explained error, if any.
    @Test(arguments: [(false, nil), (true, CurrencyError.settingsUnreadable)] as [(Bool, CurrencyError?)])
    func `A read explains only an unreadable choice`(failsLoading: Bool, error: CurrencyError?) async {
        let model = CurrencySettingsModel()

        await model.load(from: .inMemory(StoredValue(failsLoading: failsLoading)))

        #expect(model.error == error)
    }

    /// A change to a choice that can't be read explains the read, not a save.
    @Test func `A change to an unreadable choice explains the read`() async {
        let model = CurrencySettingsModel()

        model.select(.coinbase)
        await model.run(model.attempt, with: .inMemory(StoredValue(failsLoading: true)))

        #expect(model.error == .settingsUnreadable)
    }

    /// A tap saves its change once, ignoring taps while it waits, and the store shows it to every window.
    @Test func `A choice is saved once and reaches every window`() async {
        let settings = StoredValue<CurrencySettings>()
        let store = CurrencyStore.inMemory(settings)
        let model = CurrencySettingsModel()
        let expected = CurrencySettings(rateSource: .coinbase)

        model.select(.coinbase)
        model.select(.europeanCentralBank)
        await model.run(model.attempt, with: store)

        #expect(store.settings == expected)
        #expect(await settings.value == expected)
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
        let http = HTTPResponses.currency(error: .transport(.notConnectedToInternet),
                                          failingMethod: CurrencyResponses.coinbasePath)
        let settings = StoredValue(CurrencySettings(rateSource: .europeanCentralBank, currencyCode: "JPY"),
                                   failsSaving: failsSaving)
        let model = CurrencySettingsModel()

        model.select(source)
        await model.run(model.attempt, with: .inMemory(settings, http: http))

        #expect(model.error == error)
    }
}
