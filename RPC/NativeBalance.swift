public import Foundation

/// A wallet's native SOL balance and optional USD valuation returned by DAS.
public struct NativeBalance: Decodable, Sendable {
    /// The wallet's native SOL balance in lamports.
    public let lamports: UInt64
    /// The USD price of one SOL, if available.
    public let pricePerSOL: Decimal?
    /// The USD value of the wallet's native SOL, if available.
    public let totalPrice: Decimal?

    /// Creates a native balance with its optional USD prices.
    ///
    /// - Parameters:
    ///   - lamports: The native SOL balance in lamports.
    ///   - pricePerSOL: The USD unit price, or `nil` if unknown.
    ///   - totalPrice: The USD holding value, or `nil` if unknown.
    public init(lamports: UInt64, pricePerSOL: Decimal?, totalPrice: Decimal?) {
        self.lamports = lamports
        self.pricePerSOL = pricePerSOL
        self.totalPrice = totalPrice
    }

    private enum CodingKeys: String, CodingKey {
        case lamports
        case pricePerSOL = "price_per_sol"
        case totalPrice = "total_price"
    }
}
