import Foundation

extension PaymentToken {
    /// Placeholder tokens until payments read the account's holdings: two with prices and one without.
    static let samples = [
        PaymentToken(symbol: "SOL", balance: Decimal(string: "1.23")!, price: Decimal(string: "143.87"), decimals: 9),
        PaymentToken(symbol: "USDC", balance: 40, price: 1, decimals: 6),
        PaymentToken(symbol: "BONK", balance: 1_200_000, price: nil, decimals: 5),
    ]
}
