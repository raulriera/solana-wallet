import Encoding
import Foundation
@testable import Privacy
import RPC
import Testing

/// Indexer JSON for shielded transactions and tree proofs, as Helius's Solana Rings indexer encodes
/// them.
///
/// Confidential transactions are rows of the transaction streams; proofless deposits are rows of
/// the encrypted-output stream. Hashes, tags, nullifiers, and addresses are base 58; keys, salts,
/// and payloads are base 64.
enum IndexerResponses {
    /// The UTXO root position of every fixed proof that ``proofs(answering:)`` returns.
    static let utxoRootIndex: UInt16 = 31

    /// The nullifier root position of every fixed proof that ``proofs(answering:)`` returns.
    static let nullifierRootIndex: UInt16 = 87

    /// Answers a spend's reads before its proof: a nullifier-account read finds the program's
    /// accounts at the given addresses and no account elsewhere, and a proof read gets
    /// ``proofs(answering:)``.
    ///
    /// - Parameters:
    ///   - request: The RPC or indexer request.
    ///   - queued: The nullifier accounts that the program already created.
    /// - Returns: The JSON-RPC response and its HTTP metadata.
    /// - Throws: A test failure if the request is neither read.
    static func spendReads(answering request: URLRequest, queued: Set<String> = []) throws -> (Data, URLResponse) {
        let body = try requestBody(request)
        guard body["method"] as? String == GetMultipleAccounts.method else { return try proofs(answering: request) }
        let addresses = try #require((body["params"] as? [Any])?.first as? [String])
        let owner = try ShieldedPool.program.value
        let account = #"{"owner":"\#(owner)","lamports":1,"executable":false,"data":["AAAAAAAAAAA=","base64"]}"#
        let accounts = addresses.map { queued.contains($0) ? account : "null" }.joined(separator: ",")
        return try reply(to: request, payload: #""result":{"context":{"slot":1},"value":[\#(accounts)]}"#)
    }

    /// Answers a `getMerkleProofs` or `getNonInclusionProofs` request with one fixed proof per
    /// requested leaf, in order, in the requested tree.
    ///
    /// Paths are zero; the UTXO root is 1 at ``utxoRootIndex``, and the nullifier root is 2 at
    /// ``nullifierRootIndex``, with each nullifier between the low element 0 and the high element
    /// r - 1.
    ///
    /// - Parameter request: The indexer request.
    /// - Returns: The JSON-RPC response and its HTTP metadata.
    /// - Throws: A test failure if the request isn't a proof read.
    static func proofs(answering request: URLRequest) throws -> (Data, URLResponse) {
        let (method, tree, leaves) = try proofRead(request)
        let zero = Base58.encode([UInt8](repeating: 0, count: 32))
        let highest = Base58.encode(try fixtureBytes("30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000000"))
        let root = { (value: UInt8) in Base58.encode([UInt8](repeating: 0, count: 31) + [value]) }
        let context = #""merkleContext":{"treeType":\#(method == "getMerkleProofs" ? 1 : 2),"tree":"\#(tree)"}"#
        let proofs = leaves.map { leaf in
            method == "getMerkleProofs"
                ? #"{"leaf":"\#(leaf)",\#(context),"path":[\#(paths(zero, count: 32))],"leafIndex":0,"#
                    + #""root":"\#(root(1))","rootSeq":1,"rootIndex":\#(utxoRootIndex)}"#
                : #"{"leaf":"\#(leaf)",\#(context),"path":[\#(paths(zero, count: 40))],"lowElement":"\#(zero)","#
                    + #""lowElementIndex":0,"highElement":"\#(highest)","highElementIndex":1,"root":"\#(root(2))","#
                    + #""rootSeq":1,"rootIndex":\#(nullifierRootIndex)}"#
        }
        return try reply(to: request, payload: #""result":{"context":{"slot":1},"proofs":[\#(proofs.joined(separator: ","))]}"#)
    }

    /// Answers a proof read with the proofs of the requested tree from a vector's results, after
    /// checking that the request asks for exactly their leaves, in order.
    ///
    /// - Parameters:
    ///   - results: Each tree's proofs, which name their tree.
    ///   - request: The indexer request.
    /// - Returns: The JSON-RPC response and its HTTP metadata.
    /// - Throws: A test failure if no result names the tree, or the leaves differ.
    static func proofs(from results: [[JSONValue]], answering request: URLRequest) throws -> (Data, URLResponse) {
        let (_, tree, leaves) = try proofRead(request)
        let proofs = try #require(results.first { proofs in
            proofs.contains { $0.member("merkleContext")?.member("tree") == .string(tree) }
        })
        try #require(proofs.map { $0.member("leaf") } == leaves.map { .string($0) })
        let text = String(decoding: try JSONValue.object(["context": .object(["slot": .number(1)]), "proofs": .array(proofs)]).data,
                          as: UTF8.self)
        return try reply(to: request, payload: #""result":\#(text)"#)
    }

    /// Reads a proof request's method, tree account, and leaves.
    ///
    /// - Parameter request: The indexer request.
    /// - Returns: The method, the tree account, and the base-58 leaves.
    /// - Throws: A test failure if the request isn't a proof read.
    private static func proofRead(_ request: URLRequest) throws -> (method: String, tree: String, leaves: [String]) {
        let body = try requestBody(request)
        let params = try #require(body["params"] as? [String: Any])
        return (try #require(body["method"] as? String), try #require(params["treeAccount"] as? String),
                try #require(params["leaves"] as? [String]))
    }

    /// Repeats a quoted base-58 hash as a path.
    ///
    /// - Parameters:
    ///   - hash: The base-58 hash.
    ///   - count: The number of siblings.
    /// - Returns: The quoted hashes, joined by commas.
    private static func paths(_ hash: String, count: Int) -> String {
        Array(repeating: "\"\(hash)\"", count: count).joined(separator: ",")
    }

    /// The base-58 text of a 64-byte signature whose bytes all equal `byte`.
    ///
    /// - Parameter byte: The repeated byte.
    /// - Returns: A signature in base 58.
    static func signature(_ byte: UInt8) -> String {
        Base58.encode([UInt8](repeating: byte, count: 64))
    }

    /// A row of a transaction stream.
    ///
    /// - Parameter transaction: A confidential transaction, or one without outputs that only spends.
    /// - Returns: The row's JSON object.
    static func row(_ transaction: ShieldedTransaction) -> String {
        let nullifiers = transaction.nullifiers.map { "\"\(Base58.encode($0))\"" }.joined(separator: ",")
        return """
            {"slot":\(transaction.slot),"txSignature":"\(transaction.signature)","eventIndex":\(transaction.eventIndex ?? 0),\
            "txViewingPk":\(base64(transaction.transactionViewingKey)),"salt":\(base64(transaction.salt)),\
            "outputSlots":[\(transaction.outputs.map(output).joined(separator: ","))],"messages":[],\
            "nullifiers":[\(nullifiers)],"proofless":\(transaction.isProofless)}
            """
    }

    /// A row of the encrypted-output stream.
    ///
    /// - Parameter deposit: A proofless deposit with one output.
    /// - Returns: The row's JSON object.
    static func match(_ deposit: ShieldedTransaction) -> String {
        let output = deposit.outputs.map(output).joined()
        return #"{"slot":\#(deposit.slot),"txSignature":"\#(deposit.signature)","outputSlot":\#(output),"txViewingPk":null,"salt":null}"#
    }

    /// A JSON-RPC result member holding a stream's only page.
    ///
    /// - Parameters:
    ///   - rows: The rows' JSON objects.
    ///   - field: The `transactions` or `matches` field name.
    ///   - scanned: The position that the scan reached.
    ///   - outputTreeID: The newest tree that isn't paused, or `nil` to report none.
    /// - Returns: The member, for ``reply(to:payload:status:headers:id:)``.
    static func page(_ rows: [String], in field: String, scanned: String, outputTreeID: UInt16? = nil) -> String {
        let tree = outputTreeID.map { #","outputTreeId":\#($0)"# } ?? ""
        return #""result":{"context":{"slot":2},"\#(field)":[\#(rows.joined(separator: ","))],"nextCursor":null,"#
            + #""scannedThrough":"\#(scanned)"\#(tree)}"#
    }

    /// An output slot with its context.
    ///
    /// - Parameter output: The output.
    /// - Returns: The output slot's JSON object.
    private static func output(_ output: ShieldedOutput) -> String {
        """
        {"viewTag":"\(Base58.encode(output.viewTag))","outputContext":{"hash":"\(Base58.encode(output.utxoHash))",\
        "treeId":\(output.treeID),"leafIndex":\(output.leafIndex)},"payload":"\(Data(output.payload).base64EncodedString())"}
        """
    }

    /// Encodes optional bytes as a base-64 JSON string.
    ///
    /// - Parameter bytes: The bytes, or `nil`.
    /// - Returns: The quoted base-64 text, or `null`.
    private static func base64(_ bytes: [UInt8]?) -> String {
        bytes.map { "\"\(Data($0).base64EncodedString())\"" } ?? "null"
    }
}
