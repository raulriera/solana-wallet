import Foundation
import Testing
@testable import widgets

struct CurrencySettingsTests {
    @Test(arguments: [
        (CurrencySettings(currencyCode: "JPY"), "de_DE", nil),
        (CurrencySettings(rateSource: .europeanCentralBank), "de_DE", "EUR"),
        (CurrencySettings(rateSource: .europeanCentralBank, currencyCode: "GBP"), "de_DE", "GBP"),
    ] as [(CurrencySettings, String, String?)])
    func `The choice names the currency that values show in`(settings: CurrencySettings, locale: String,
                                                              currency: String?) {
        #expect(settings.currency(in: Locale(identifier: locale)) == currency)
    }
}
