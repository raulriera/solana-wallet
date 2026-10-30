public import Foundation

/// The market valuation of a holding.
public struct Valuation: Codable, Sendable, Equatable {
    /// The price of one decimal-adjusted unit.
    public let pricePerUnit: Decimal?
    /// The value of the whole holding.
    public let total: Decimal?
    public let currency: String?
    /// The 24-hour price change as a fraction, where `0.0129` is a 1.29% rise.
    public let dayChange: Decimal?

    /// Creates a valuation.
    ///
    /// - Parameters:
    ///   - pricePerUnit: The price of one unit, or `nil` if unknown.
    ///   - total: The value of the holding, or `nil` if unknown.
    ///   - currency: The quote currency, or `nil` if unknown.
    ///   - dayChange: The 24-hour price change as a fraction, or `nil` if unknown.
    public init(pricePerUnit: Decimal?, total: Decimal?, currency: String?, dayChange: Decimal? = nil) {
        self.pricePerUnit = pricePerUnit
        self.total = total
        self.currency = currency
        self.dayChange = dayChange
    }
}
