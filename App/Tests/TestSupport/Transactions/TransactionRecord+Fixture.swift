import Foundation
@testable import RPC
@testable import widgets

extension TransactionRecord {
    static func fixture(_ kind: Kind, signature: String = "signature", account: UUID,
                        network: Network = .devnet) -> TransactionRecord {
        TransactionRecord(kind, from: account,
                          outcome: TransactionOutcome(signature: signature, network: network, lastValidBlockHeight: 550,
                                                      status: .pending))
    }
}
