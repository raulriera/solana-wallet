import Foundation
import Testing
@testable import widgets

/// Checks which currency the saved choice shows values in.
struct CurrencySettingsTests {
    /// Without a rate source, values keep the prices' own currency; with one, a chosen currency wins over the region's.
    /// - Parameters:
    ///   - settings: The saved choice.
    ///   - locale: The device's locale identifier.
    ///   - currency: The currency that values show in, if any.
    @Test(arguments: [
        (CurrencySettings(), "de_DE", nil),
        (CurrencySettings(currencyCode: "JPY"), "de_DE", nil),
        (CurrencySettings(rateSource: .europeanCentralBank), "de_DE", "EUR"),
        (CurrencySettings(rateSource: .coinbase), "ja_JP", "JPY"),
        (CurrencySettings(rateSource: .europeanCentralBank, currencyCode: "GBP"), "de_DE", "GBP"),
    ] as [(CurrencySettings, String, String?)])
    func `The choice names the currency that values show in`(settings: CurrencySettings, locale: String,
                                                              currency: String?) {
        #expect(settings.currency(in: Locale(identifier: locale)) == currency)
    }
}
