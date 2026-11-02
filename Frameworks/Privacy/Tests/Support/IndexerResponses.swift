import Encoding
import Foundation
import RPC
import Testing
import Transactions
@testable import Privacy

enum IndexerResponses {
    static func spendReads(answering request: URLRequest, queued: Set<String> = []) throws -> (Data, URLResponse) {
        let body = try requestBody(request)
        try #require(body["method"] as? String == GetMultipleAccounts.method)
        let addresses = try #require((body["params"] as? [Any])?.first as? [String])
        let account = AccountReplies.account(owner: try ShieldedPool.program.value, data: [UInt8](repeating: 0, count: 8))
        let accounts = addresses.map { queued.contains($0) ? account : nil }
        return try reply(to: request, payload: #""result":\#(AccountReplies.accounts(accounts))"#)
    }

    static func signature(_ byte: UInt8) -> String {
        Base58.encode([UInt8](repeating: byte, count: 64))
    }

    static func row(_ transaction: ShieldedTransaction) -> String {
        IndexerReplies.transaction(
            signature: transaction.signature, slot: transaction.slot, eventIndex: transaction.eventIndex ?? 0,
            viewingKey: base64(transaction.transactionViewingKey), salt: base64(transaction.salt),
            outputs: transaction.outputs.map(output), nullifiers: transaction.nullifiers.map { Base58.encode($0) },
            isProofless: transaction.isProofless
        )
    }

    static func match(_ deposit: ShieldedTransaction) -> String {
        IndexerReplies.match(signature: deposit.signature, slot: deposit.slot, output: deposit.outputs.map(output).joined())
    }

    private static func output(_ output: ShieldedOutput) -> String {
        IndexerReplies.output(viewTag: Base58.encode(output.viewTag), hash: Base58.encode(output.utxoHash),
                              treeID: output.treeID, leafIndex: output.leafIndex,
                              payload: Data(output.payload).base64EncodedString())
    }

    private static func base64(_ bytes: [UInt8]?) -> String? {
        bytes.map { Data($0).base64EncodedString() }
    }
}
