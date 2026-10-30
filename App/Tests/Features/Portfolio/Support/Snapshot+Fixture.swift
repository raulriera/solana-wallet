import RPC
@testable import Portfolio

extension Snapshot {
    static func fixture(owner: String, lamports: UInt64) -> Snapshot {
        Snapshot(owner: owner, network: .devnet, holdings: [
            Holding(id: .nativeSOL, amount: Amount(units: lamports, decimals: 9), name: "Solana", symbol: "SOL",
                    imageURL: nil, valuation: nil),
        ])
    }
}
