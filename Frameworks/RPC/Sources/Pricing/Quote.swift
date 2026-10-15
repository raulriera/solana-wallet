public import Foundation

/// A provider-neutral market price for one whole, decimal-adjusted token.
///
/// Providers map their responses into this value before returning it to consumers.
public struct Quote: Sendable, Equatable {
    /// The quoted price of one whole token, without binary floating-point conversion.
    public let pricePerUnit: Decimal
    /// The currency supplied by the price source, such as `USD`.
    public let currency: String
    /// The price change over the last 24 hours as a fraction, so `0.0129` is a 1.29% rise, or `nil` when
    /// the source doesn't supply one. An unknown change is never zero.
    public let dayChange: Decimal?

    /// Creates a normalized quote without tying consumers to a provider's response format.
    /// - Parameters:
    ///   - pricePerUnit: The nonnegative price of one whole token.
    ///   - currency: The quote currency.
    ///   - dayChange: The 24-hour price change as a fraction, or `nil` when unknown.
    public init(pricePerUnit: Decimal, currency: String, dayChange: Decimal?) {
        self.pricePerUnit = pricePerUnit
        self.currency = currency
        self.dayChange = dayChange
    }
}
