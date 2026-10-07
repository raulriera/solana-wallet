public import Foundation

/// The available market valuation of a holding in its quoted currency.
public struct Valuation: Codable, Sendable, Equatable {
    /// The price of one decimal-adjusted unit, if known.
    public let pricePerUnit: Decimal?
    /// The value of the entire holding, if known.
    public let total: Decimal?
    /// The currency in which the price and total are quoted, if known.
    public let currency: String?
    /// The independent quote's retrieval time, or `nil` when the source doesn't supply one.
    /// This time doesn't describe when the wallet's balance was retrieved.
    public let fetchedAt: Date?
    /// The independent quote's 24-hour price change as a fraction, so `0.0129` is a 1.29% rise,
    /// or `nil` when unknown. Snapshots saved without it restore as unknown.
    public let dayChange: Decimal?

    /// Creates a valuation while preserving unknown prices.
    ///
    /// - Parameters:
    ///   - pricePerUnit: The unit price, or `nil` if unavailable.
    ///   - total: The holding value, or `nil` if unavailable.
    ///   - currency: The quote currency, or `nil` if unknown.
    ///   - fetchedAt: The quote retrieval time, or `nil` if unavailable.
    ///   - dayChange: The 24-hour price change as a fraction, or `nil` if unknown.
    public init(pricePerUnit: Decimal?, total: Decimal?, currency: String?, fetchedAt: Date? = nil,
                dayChange: Decimal? = nil) {
        self.pricePerUnit = pricePerUnit
        self.total = total
        self.currency = currency
        self.fetchedAt = fetchedAt
        self.dayChange = dayChange
    }
}
