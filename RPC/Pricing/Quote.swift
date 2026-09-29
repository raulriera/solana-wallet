public import Foundation

/// A provider-neutral market price for one whole, decimal-adjusted token.
public struct Quote: Codable, Sendable, Equatable {
    /// The quoted price of one whole token, without binary floating-point conversion.
    public let pricePerUnit: Decimal
    /// The currency supplied by the price source, such as `USD`.
    public let currency: String
    /// The time the quote was retrieved, independent of any wallet balance refresh.
    ///
    /// This is not the time of the underlying trade or a guarantee of market freshness.
    public let fetchedAt: Date
    /// The source's on-chain block reference, or `nil` when unavailable.
    public let blockID: UInt64?

    /// Creates a normalized quote without tying consumers to a provider's response format.
    /// - Parameters:
    ///   - pricePerUnit: The nonnegative price of one whole token.
    ///   - currency: The quote currency.
    ///   - fetchedAt: The time the quote was retrieved.
    ///   - blockID: The on-chain block reference, or `nil` when unavailable.
    public init(pricePerUnit: Decimal, currency: String, fetchedAt: Date, blockID: UInt64? = nil) {
        self.pricePerUnit = pricePerUnit
        self.currency = currency
        self.fetchedAt = fetchedAt
        self.blockID = blockID
    }
}
