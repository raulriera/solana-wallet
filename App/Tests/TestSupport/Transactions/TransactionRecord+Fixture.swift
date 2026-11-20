import Foundation
import RPC
@testable import widgets

extension TransactionRecord {
    static func fixture(_ kind: Kind, signature: String = "signature", account: UUID, network: Network = .devnet,
                        outcome: TransactionOutcome? = nil) -> TransactionRecord {
        var record = TransactionRecord(kind, from: account,
                                       submission: Submission(signature: signature, network: network,
                                                              lastValidBlockHeight: 550))
        if let outcome { record.settle(outcome, at: Date(timeIntervalSinceReferenceDate: 0)) }
        return record
    }
}
