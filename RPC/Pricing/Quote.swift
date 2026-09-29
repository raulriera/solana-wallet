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

    /// Creates a normalized quote without tying consumers to a provider's response format.
    /// - Parameters:
    ///   - pricePerUnit: The nonnegative price of one whole token.
    ///   - currency: The quote currency.
    ///   - fetchedAt: The time the quote was retrieved.
    public init(pricePerUnit: Decimal, currency: String, fetchedAt: Date) {
        self.pricePerUnit = pricePerUnit
        self.currency = currency
        self.fetchedAt = fetchedAt
    }
}
