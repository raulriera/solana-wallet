import Foundation
import RPC
@testable import widgets

// swift-format-ignore: NeverUseForceTry
extension TransactionRecord {
    private static let preparation = try! PreparationFixture.preparation()

    static func fixture(_ kind: Kind, signature: String = "signature", account: UUID,
                        network: Network = .devnet) -> TransactionRecord {
        TransactionRecord(kind, from: account, transaction: preparation.transaction,
                          outcome: Outcome(signature: signature, network: network,
                                           lastValidBlockHeight: preparation.source.lastValidBlockHeight,
                                           status: .pending))
    }
}
