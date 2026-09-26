public import Foundation

/// The available market valuation of a holding in its quoted currency.
public struct Valuation: Codable, Sendable, Equatable {
    /// The price of one decimal-adjusted unit, if known.
    public let pricePerUnit: Decimal?
    /// The value of the entire holding, if known.
    public let total: Decimal?
    /// The currency in which the price and total are quoted, if known.
    public let currency: String?

    /// Creates a valuation while preserving unknown prices.
    ///
    /// - Parameters:
    ///   - pricePerUnit: The unit price, or `nil` if unavailable.
    ///   - total: The holding value, or `nil` if unavailable.
    ///   - currency: The quote currency, or `nil` if unknown.
    public init(pricePerUnit: Decimal?, total: Decimal?, currency: String?) {
        self.pricePerUnit = pricePerUnit
        self.total = total
        self.currency = currency
    }
}
