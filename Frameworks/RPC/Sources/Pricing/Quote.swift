public import Foundation

/// A provider-neutral market price for one whole, decimal-adjusted token.
///
/// Providers map their responses into this value before returning it to consumers.
/// Its Codable representation uses our field names independently of any provider.
public struct Quote: Codable, Sendable, Equatable {
    /// The quoted price of one whole token, without binary floating-point conversion.
    public let pricePerUnit: Decimal
    /// The currency supplied by the price source, such as `USD`.
    public let currency: String
    /// The time the quote was retrieved, independent of any wallet balance refresh.
    ///
    /// This is not the time of the underlying trade or a guarantee of market freshness.
    public let fetchedAt: Date
    /// The price change over the last 24 hours as a fraction, so `0.0129` is a 1.29% rise, or `nil` when
    /// the source doesn't supply one. An unknown change is never zero.
    public let dayChange: Decimal?

    /// Creates a normalized quote without tying consumers to a provider's response format.
    /// - Parameters:
    ///   - pricePerUnit: The nonnegative price of one whole token.
    ///   - currency: The quote currency.
    ///   - fetchedAt: The time the quote was retrieved.
    ///   - dayChange: The 24-hour price change as a fraction, or `nil` when unknown.
    public init(pricePerUnit: Decimal, currency: String, fetchedAt: Date, dayChange: Decimal? = nil) {
        self.pricePerUnit = pricePerUnit
        self.currency = currency
        self.fetchedAt = fetchedAt
        self.dayChange = dayChange
    }
}
