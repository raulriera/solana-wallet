public import Foundation

/// A market price for one whole token.
///
/// A quote decodes from JSON such as `{"pricePerUnit": 96.14, "currency": "USD", "dayChange": 0.05}`. A missing or
/// malformed `dayChange` decodes as an unknown change.
public struct Quote: Sendable, Equatable, Decodable {
    /// The price of one whole token.
    public let pricePerUnit: Decimal
    public let currency: String
    /// The 24-hour price change as a fraction, where `0.0129` is a 1.29% rise.
    public let dayChange: Decimal?

    /// Creates a quote.
    ///
    /// - Parameters:
    ///   - pricePerUnit: The nonnegative price of one whole token.
    ///   - currency: The quote currency.
    ///   - dayChange: The 24-hour price change as a fraction, or `nil` if unknown.
    public init(pricePerUnit: Decimal, currency: String, dayChange: Decimal?) {
        self.pricePerUnit = pricePerUnit
        self.currency = currency
        self.dayChange = dayChange
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pricePerUnit = try container.decode(Decimal.self, forKey: .pricePerUnit)
        currency = try container.decode(String.self, forKey: .currency)
        dayChange = try? container.decodeIfPresent(Decimal.self, forKey: .dayChange)
    }

    /// Whether the price is a nonnegative number and the currency is an ISO currency code.
    var isValid: Bool {
        !pricePerUnit.isNaN && pricePerUnit >= 0 && Locale.commonISOCurrencyCodes.contains(currency)
    }

    /// The field names in a quote's JSON.
    private enum CodingKeys: String, CodingKey {
        case pricePerUnit
        case currency
        case dayChange
    }
}
