import Foundation
import Testing
@testable import widgets

struct CurrencyNameFormatStyleTests {
    @Test(arguments: [
        ("en_US", "EUR", "Euro"),
        ("de_DE", "USD", "US-Dollar"),
        ("en_US", "ZZZ", "ZZZ"),
    ])
    func `A currency shows its name in the locale, or its code when it has no name`(locale: String, code: String,
                                                                                  shown: String) {
        #expect(CurrencyNameFormatStyle.currencyName.locale(Locale(identifier: locale)).format(code) == shown)
    }
}
