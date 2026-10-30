import Foundation
import RPC
@testable import widgets

extension TransactionRecord {
    static func fixture(_ kind: Kind, signature: String = "signature", account: UUID, network: Network = .devnet,
                        status: Status = .pending, created: TimeInterval = 0,
                        settled: TimeInterval? = nil) -> TransactionRecord {
        var record = TransactionRecord(kind, from: account,
                                       submission: Submission(signature: signature, network: network,
                                                              lastValidBlockHeight: 550),
                                       created: Date(timeIntervalSinceReferenceDate: created))
        record.status = status
        record.settled = settled.map(Date.init(timeIntervalSinceReferenceDate:))
        return record
    }
}
