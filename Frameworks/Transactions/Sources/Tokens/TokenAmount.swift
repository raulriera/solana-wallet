/// An exact quantity expressed in integer units and decimal places.
public struct TokenAmount: Codable, Hashable, Sendable {
    /// The quantity in the asset's smallest units.
    public let amount: UInt64
    public let decimals: UInt8

    /// Creates a token amount.
    ///
    /// - Parameters:
    ///   - amount: The quantity in the asset's smallest units.
    ///   - decimals: The number of decimal places.
    public init(amount: UInt64, decimals: UInt8) {
        self.amount = amount
        self.decimals = decimals
    }

    /// Creates a SOL amount from lamports.
    ///
    /// - Parameter lamports: The amount in lamports, SOL's smallest unit.
    public init(lamports: UInt64) {
        self.init(amount: lamports, decimals: 9)
    }
}
