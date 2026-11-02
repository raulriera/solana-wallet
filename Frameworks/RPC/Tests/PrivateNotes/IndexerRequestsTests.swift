import Foundation
import Testing
@testable import RPC

struct IndexerRequestsTests {
    @Test(arguments: [
        (GetShieldedTransactionsByTags(tags: ["a"], cursor: nil) as any RPCRequest, #"{"tags":["a"]}"#),
        (GetShieldedTransactionsByTags(tags: ["a"], cursor: "AQ=="), #"{"cursor":"AQ==","tags":["a"]}"#),
        (GetEncryptedUtxosByTags(tags: ["a", "b"], cursor: nil), #"{"tags":["a","b"]}"#),
        (GetEncryptedUtxosByTags(tags: ["a"], cursor: "AQ=="), #"{"cursor":"AQ==","tags":["a"]}"#),
        (GetShieldedTransactionsByNullifiers(nullifiers: ["n"], cursor: nil), #"{"nullifiers":["n"]}"#),
        (GetShieldedTransactionsByNullifiers(nullifiers: ["n"], cursor: "AQ=="), #"{"cursor":"AQ==","nullifiers":["n"]}"#),
    ])
    func `Requests send their values and an optional cursor`(request: any RPCRequest, expected: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        #expect(String(decoding: try encoder.encode(request), as: UTF8.self) == expected)
    }
}
