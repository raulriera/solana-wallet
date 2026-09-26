public import Foundation

/// Market prices returned by DAS, with missing values preserved as unknown.
public struct Price: Decodable, Sendable {
    /// The price of one decimal-adjusted token, if available.
    public let perToken: Decimal?
    /// The value of the owner's holding, if available.
    public let total: Decimal?
    /// The quote currency supplied by the provider.
    public let currency: String?

    /// Creates price information from the provider's quote.
    ///
    /// - Parameters:
    ///   - perToken: The unit price, or `nil` if unknown.
    ///   - total: The holding's value, or `nil` if unknown.
    ///   - currency: The quote currency, or `nil` if unknown.
    public init(perToken: Decimal?, total: Decimal?, currency: String?) {
        self.perToken = perToken
        self.total = total
        self.currency = currency
    }

    private enum CodingKeys: String, CodingKey {
        case perToken = "price_per_token"
        case total = "total_price"
        case currency
    }
}
