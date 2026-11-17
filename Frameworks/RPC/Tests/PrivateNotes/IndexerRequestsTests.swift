import Foundation
import Testing
@testable import RPC

struct IndexerRequestsTests {
    @Test(arguments: [
        (IndexerPageRequest(query: GetShieldedTransactionsByTags(tags: ["a"]), checkpoint: .start, limit: 250)
            as any RPCRequest, #"{"limit":250,"tags":["a"]}"#),
        (IndexerPageRequest(query: GetEncryptedUtxosByTags(tags: ["a", "b"]),
                            checkpoint: IndexerCheckpoint(afterSlot: 9, paginationToken: nil), limit: 125),
         #"{"filters":{"slot":{"gt":9}},"limit":125,"tags":["a","b"]}"#),
        (IndexerPageRequest(query: GetShieldedTransactionsByNullifiers(nullifiers: ["n"]),
                            checkpoint: IndexerCheckpoint(afterSlot: 9, paginationToken: "1:10:s"), limit: 1),
         #"{"filters":{"slot":{"gt":9}},"limit":1,"nullifiers":["n"],"paginationToken":"1:10:s"}"#),
        (GetMerkleProofs(treeAccount: "t", leaves: ["a", "b"]), #"{"leaves":["a","b"],"treeAccount":"t"}"#),
    ])
    func `Requests send their values with their checkpoint and limit`(request: any RPCRequest, expected: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        #expect(String(decoding: try encoder.encode(request), as: UTF8.self) == expected)
    }
}
