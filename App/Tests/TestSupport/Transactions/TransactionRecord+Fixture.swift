import Foundation
import RPC
@testable import widgets

extension TransactionRecord {
    /// Creates a devnet record whose blockhash is valid through block height 550.
    /// - Parameters:
    ///   - kind: What the transaction does.
    ///   - signature: The record's signature.
    ///   - account: The account that sent it.
    ///   - status: Whether it settled, and how.
    ///   - created: When it was sent, in seconds after 1 January 2001.
    ///   - settled: When it settled, in seconds after 1 January 2001, or `nil` while it's pending.
    /// - Returns: The record.
    static func fixture(_ kind: Kind, signature: String = "signature", account: UUID, status: Status = .pending,
                        created: TimeInterval = 0, settled: TimeInterval? = nil) -> TransactionRecord {
        var record = TransactionRecord(kind, from: account,
                                       submission: Submission(signature: signature, network: .devnet,
                                                              lastValidBlockHeight: 550),
                                       created: Date(timeIntervalSinceReferenceDate: created))
        record.status = status
        record.settled = settled.map(Date.init(timeIntervalSinceReferenceDate:))
        return record
    }
}
