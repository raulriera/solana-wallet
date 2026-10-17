import Encoding
import Foundation
import Testing
@testable import RPC

/// Fixture JSON for Solana Rings indexer responses, built from repeated bytes.
enum IndexerFixtures {
    /// The base-58 text of 32 bytes that all equal `byte`.
    /// - Parameter byte: The repeated byte.
    /// - Returns: A 32-byte hash, tag, or nullifier in base 58.
    static func hash(_ byte: UInt8) -> String { Base58.encode(bytes(byte)) }

    /// The 32 bytes of a fixture hash.
    /// - Parameter byte: The repeated byte.
    /// - Returns: Thirty-two copies of `byte`.
    static func bytes(_ byte: UInt8) -> [UInt8] { Array(repeating: byte, count: 32) }

    /// The base-58 text of a 64-byte signature whose bytes all equal `byte`.
    /// - Parameter byte: The repeated byte.
    /// - Returns: A signature in base 58.
    static func signature(_ byte: UInt8) -> String { Base58.encode(Array(repeating: byte, count: 64)) }

    /// A 33-byte transaction viewing key in base 64.
    static let viewingKey = Data(repeating: 2, count: 33).base64EncodedString()

    /// A 16-byte salt in base 64.
    static let salt = Data(repeating: 5, count: 16).base64EncodedString()

    /// An output slot with its context.
    /// - Parameters:
    ///   - tag: The view tag's repeated byte.
    ///   - hash: The UTXO hash's repeated byte.
    ///   - leafIndex: The leaf's position.
    /// - Returns: The output slot's JSON object.
    static func output(tag: UInt8, hash: UInt8, leafIndex: Int) -> String {
        """
        {"viewTag":"\(Self.hash(tag))","outputContext":{"hash":"\(Self.hash(hash))",\
        "tree":"\(Self.hash(9))","treeId":0,"leafIndex":\(leafIndex)},"payload":"AQID"}
        """
    }

    /// A shielded transaction.
    /// - Parameters:
    ///   - signature: The signature's repeated byte.
    ///   - slot: The including slot.
    ///   - eventIndex: The event's position.
    ///   - proofless: Whether it is a proofless deposit, which has no viewing key or salt.
    ///   - outputs: Output slot objects.
    ///   - nullifiers: The nullifiers' repeated bytes.
    /// - Returns: The transaction's JSON object.
    static func transaction(signature: UInt8, slot: Int, eventIndex: Int = 0, proofless: Bool = false,
                            outputs: [String] = [], nullifiers: [UInt8] = []) -> String {
        let keys = proofless ? #""txViewingPk":null,"salt":null"# : #""txViewingPk":"\#(viewingKey)","salt":"\#(salt)""#
        return """
            {"slot":\(slot),"txSignature":"\(Self.signature(signature))","eventIndex":\(eventIndex),\(keys),\
            "outputSlots":[\(outputs.joined(separator: ","))],"messages":[],\
            "nullifiers":[\(nullifiers.map { "\"\(hash($0))\"" }.joined(separator: ","))],"proofless":\(proofless)}
            """
    }

    /// An encrypted-output match.
    /// - Parameters:
    ///   - signature: The signature's repeated byte.
    ///   - slot: The including slot.
    ///   - output: The output slot object.
    ///   - keyed: Whether the transaction has a viewing key and salt, so it isn't a proofless deposit.
    /// - Returns: The match's JSON object.
    static func match(signature: UInt8, slot: Int, output: String, keyed: Bool = false) -> String {
        let keys = keyed ? #""txViewingPk":"\#(viewingKey)","salt":"\#(salt)""# : #""txViewingPk":null,"salt":null"#
        return #"{"slot":\#(slot),"txSignature":"\#(Self.signature(signature))","outputSlot":\#(output),\#(keys)}"#
    }

    /// A JSON-RPC result member holding one page.
    /// - Parameters:
    ///   - items: The rows' JSON objects.
    ///   - rows: The `transactions` or `matches` field name.
    ///   - next: The next cursor, or `nil` for `null`.
    ///   - scanned: The scanned position, or `nil` to omit it.
    ///   - outputTreeID: The output tree, or `nil` to omit it.
    /// - Returns: The member, for ``reply(to:payload:status:headers:id:)``.
    static func page(_ items: [String] = [], in rows: String = "transactions", next: String? = nil,
                     scanned: String? = nil, outputTreeID: Int? = nil) -> String {
        var fields = [#""context":{"blockTime":1,"slot":2}"#, #""\#(rows)":[\#(items.joined(separator: ","))]"#,
                      #""nextCursor":\#(next.map { "\"\($0)\"" } ?? "null")"#]
        if let scanned { fields.append(#""scannedThrough":"\#(scanned)""#) }
        if let outputTreeID { fields.append(#""outputTreeId":\#(outputTreeID)"#) }
        return #""result":{\#(fields.joined(separator: ","))}"#
    }

    /// An inclusion proof in the shape of a `getMerkleProofs` result entry.
    /// - Parameters:
    ///   - leaf: The leaf's repeated byte.
    ///   - tree: The tree account that the context names.
    ///   - treeType: The context's tree type; 1 is a UTXO tree.
    ///   - pathCount: The number of siblings, each of bytes `0x10` plus its level.
    ///   - leafIndex: The leaf's position.
    /// - Returns: The proof's JSON object, with root `0xbb` at position 499.
    static func merkleProof(leaf: UInt8, tree: String = hash(9), treeType: Int = 1, pathCount: Int = 32,
                            leafIndex: Int = 6) -> String {
        """
        {"leaf":"\(hash(leaf))","merkleContext":{"treeType":\(treeType),"tree":"\(tree)"},\
        "path":[\(path(count: pathCount))],"leafIndex":\(leafIndex),"root":"\(hash(0xbb))","rootSeq":1234,"rootIndex":499}
        """
    }

    /// A non-inclusion proof in the shape of a `getNonInclusionProofs` result entry.
    /// - Parameters:
    ///   - leaf: The nullifier's repeated byte.
    ///   - tree: The tree account that the context names.
    ///   - treeType: The context's tree type; 2 is a nullifier tree.
    ///   - pathCount: The number of siblings, each of bytes `0x10` plus its level.
    /// - Returns: The proof's JSON object, between `0x01` at position 3 and `0xfe` at position 4, with root `0xcc`
    ///   at position 99.
    static func nonInclusionProof(leaf: UInt8, tree: String = hash(9), treeType: Int = 2, pathCount: Int = 40) -> String {
        """
        {"leaf":"\(hash(leaf))","merkleContext":{"treeType":\(treeType),"tree":"\(tree)"},\
        "path":[\(path(count: pathCount))],"lowElement":"\(hash(1))","lowElementIndex":3,"highElement":"\(hash(0xfe))",\
        "highElementIndex":4,"root":"\(hash(0xcc))","rootSeq":2,"rootIndex":99}
        """
    }

    /// The siblings of a fixture path.
    /// - Parameter count: The number of siblings.
    /// - Returns: The quoted base-58 hashes of bytes `0x10` plus each level, joined by commas.
    static func path(count: Int) -> String {
        (0..<count).map { "\"\(hash(0x10 + UInt8($0)))\"" }.joined(separator: ",")
    }

    /// A JSON-RPC result member holding proofs.
    /// - Parameter proofs: The proofs' JSON objects.
    /// - Returns: The member, for ``reply(to:payload:status:headers:id:)``.
    static func proofs(_ proofs: [String]) -> String {
        #""result":{"context":{"blockTime":1,"slot":2},"proofs":[\#(proofs.joined(separator: ","))]}"#
    }

    /// Reads the method route and the JSON-RPC parameters of an indexer request.
    /// - Parameter request: The outgoing request.
    /// - Returns: The last path component and the parameters object.
    /// - Throws: A test prerequisite error if the request isn't an indexer request.
    static func call(_ request: URLRequest) throws -> (route: String, params: [String: Any]) {
        let route = try #require(request.url?.lastPathComponent)
        let params = try #require(try requestBody(request)["params"] as? [String: Any])
        return (route, params)
    }
}
