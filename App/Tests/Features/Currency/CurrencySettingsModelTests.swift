import Foundation
@testable import RPC
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CurrencySettingsModelTests {
    @Test(arguments: [(false, nil), (true, CurrencyError.settingsUnreadable)] as [(Bool, CurrencyError?)])
    func `A read explains only an unreadable choice`(failsLoading: Bool, error: CurrencyError?) async {
        let model = CurrencySettingsModel()

        await model.load(from: .inMemory(StoredValue(failsLoading: failsLoading)))

        #expect(model.error == error)
    }

    @Test func `A change to an unreadable choice explains the read`() async {
        let model = CurrencySettingsModel()

        model.select(.coinbase)
        await model.run(model.attempt, with: .inMemory(StoredValue(failsLoading: true)))

        #expect(model.error == .settingsUnreadable)
    }

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
