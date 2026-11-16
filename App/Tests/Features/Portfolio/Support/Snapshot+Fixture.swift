import RPC
import Transactions
@testable import Portfolio

extension Snapshot {
    static func fixture(owner: String, lamports: UInt64) -> Snapshot {
        Snapshot(owner: owner, network: .devnet, holdings: [
            Holding(asset: .nativeSOL, balance: TokenAmount(amount: lamports, decimals: 9),
                    imageURL: nil, valuation: nil),
        ])
    }
}
