import RPC
@testable import Portfolio

extension Snapshot {
    /// Creates a complete devnet portfolio that holds only native SOL, without wallet recovery or live addresses.
    /// - Parameters:
    ///   - owner: The test wallet's label.
    ///   - lamports: The SOL balance, which tells the results apart.
    /// - Returns: A portfolio that holds only native SOL.
    static func fixture(owner: String, lamports: UInt64) -> Snapshot {
        Snapshot(owner: owner, network: .devnet, holdings: [
            Holding(id: .nativeSOL, amount: Amount(units: lamports, decimals: 9), name: "Solana", symbol: "SOL",
                    imageURL: nil, valuation: nil),
        ])
    }
}
