import Encoding
import Foundation
import Testing
@testable import RPC

enum IndexerFixtures {
    static let hosts: [(Network, String)] = [
        (.mainnet, "dgcj4pjarvo65.cloudfront.net"), (.devnet, "d34xe1hqb2ibg2.cloudfront.net"),
    ]

    static func hash(_ byte: UInt8) -> String { Base58.encode(bytes(byte)) }

    static func bytes(_ byte: UInt8) -> [UInt8] { Array(repeating: byte, count: 32) }

    static func signature(_ byte: UInt8) -> String { Base58.encode(Array(repeating: byte, count: 64)) }

    static let viewingKey = Data(repeating: 2, count: 33).base64EncodedString()

    static let salt = Data(repeating: 5, count: 16).base64EncodedString()

    static func output(tag: UInt8, hash: UInt8, leafIndex: UInt64, payload: String = "AQID") -> String {
        IndexerReplies.output(viewTag: Self.hash(tag), hash: Self.hash(hash), treeID: 0, leafIndex: leafIndex,
                              payload: payload)
    }

    static func transaction(signature: UInt8, slot: Int, eventIndex: UInt16 = 0, proofless: Bool = false,
                            outputs: [String] = [], nullifiers: [UInt8] = []) -> String {
        IndexerReplies.transaction(signature: Self.signature(signature), slot: UInt64(slot), eventIndex: eventIndex,
                                   viewingKey: proofless ? nil : viewingKey, salt: proofless ? nil : salt,
                                   outputs: outputs, nullifiers: nullifiers.map(hash), isProofless: proofless)
    }

    static func match(signature: UInt8, slot: Int, output: String, keyed: Bool = false) -> String {
        IndexerReplies.match(signature: Self.signature(signature), slot: UInt64(slot), output: output,
                             viewingKey: keyed ? viewingKey : nil, salt: keyed ? salt : nil)
    }

    static func page(_ items: [String] = [], in rows: String = "transactions", next: String? = nil,
                     scannedThrough: String? = IndexerReplies.scannedThrough, outputTreeID: UInt16? = nil) -> String {
        let page = IndexerReplies.page(items, in: rows, next: next, scannedThrough: scannedThrough,
                                       outputTreeID: outputTreeID)
        return #""result":\#(page)"#
    }

    static func merkleProof(leaf: UInt8, tree: String = hash(9), treeType: Int = 1, pathCount: Int = 32,
                            leafIndex: Int = 6) -> String {
        merkleProof(leafHash: hash(leaf), tree: tree, treeType: treeType, pathCount: pathCount, leafIndex: leafIndex)
    }

    static func merkleProof(leafHash: String, tree: String = hash(9), treeType: Int = 1, pathCount: Int = 32,
                            leafIndex: Int = 6) -> String {
        MerkleProofReplies.proof(leaf: leafHash, tree: tree, treeType: treeType,
                                 path: (0..<pathCount).map { hash(0x10 + UInt8($0)) }, leafIndex: leafIndex,
                                 root: hash(0xbb), rootIndex: 499)
    }

    static func proofs(_ proofs: [String]) -> String {
        #""result":\#(MerkleProofReplies.result(proofs))"#
    }

    static func call(_ request: URLRequest) throws -> (route: String, params: [String: Any]) {
        let route = try #require(request.url?.lastPathComponent)
        let params = try #require(try requestBody(request)["params"] as? [String: Any])
        return (route, params)
    }
}
