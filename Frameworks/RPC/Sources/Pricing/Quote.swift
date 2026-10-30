public import Foundation

/// A market price for one whole token.
public struct Quote: Sendable, Equatable {
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
}
