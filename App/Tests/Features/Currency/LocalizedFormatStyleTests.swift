import Foundation
import Testing
@testable import widgets

struct LocalizedFormatStyleTests {
    @Test func `A caller that knows only the format style protocol replaces the locale`() {
        let locale = Locale(identifier: "de_DE")
        #expect(Self.localized(CurrencyNameFormatStyle(), in: locale).locale == locale)
    }

    private static func localized<Style: FormatStyle>(_ style: Style, in locale: Locale) -> Style {
        style.locale(locale)
    }
}
