import Foundation

extension Decimal {
    /// Creates a positive exchange rate from plain decimal text, or `nil` unless the whole text is digits with at most
    /// one period between them and is greater than zero.
    ///
    /// - Parameter text: The rate's decimal text.
    init?(exchangeRate text: String) {
        guard text.wholeMatch(of: /[0-9]+(\.[0-9]+)?/) != nil,
              let rate = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !rate.isNaN, rate > 0 else {
            return nil
        }
        self = rate
    }
}
