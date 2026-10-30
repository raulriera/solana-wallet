import Encoding
import Foundation
@testable import Privacy
import RPC
import Testing
import Transactions

enum IndexerResponses {
    static let utxoRootIndex: UInt16 = 31

    static let nullifierRootIndex: UInt16 = 87

    static func spendReads(answering request: URLRequest, queued: Set<String> = []) throws -> (Data, URLResponse) {
        let body = try requestBody(request)
        guard body["method"] as? String == GetMultipleAccounts.method else { return try proofs(answering: request) }
        let addresses = try #require((body["params"] as? [Any])?.first as? [String])
        let owner = try ShieldedPool.program.value
        let account = #"{"owner":"\#(owner)","lamports":1,"executable":false,"data":["AAAAAAAAAAA=","base64"]}"#
        let accounts = addresses.map { queued.contains($0) ? account : "null" }.joined(separator: ",")
        return try reply(to: request, payload: #""result":{"context":{"slot":1},"value":[\#(accounts)]}"#)
    }

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

    private static func proofRead(_ request: URLRequest) throws -> (method: String, tree: String, leaves: [String]) {
        let body = try requestBody(request)
        let params = try #require(body["params"] as? [String: Any])
        return (try #require(body["method"] as? String), try #require(params["treeAccount"] as? String),
                try #require(params["leaves"] as? [String]))
    }

    private static func paths(_ hash: String, count: Int) -> String {
        Array(repeating: "\"\(hash)\"", count: count).joined(separator: ",")
    }

    static func signature(_ byte: UInt8) -> String {
        Base58.encode([UInt8](repeating: byte, count: 64))
    }

    static func row(_ transaction: ShieldedTransaction) -> String {
        let nullifiers = transaction.nullifiers.map { "\"\(Base58.encode($0))\"" }.joined(separator: ",")
        return """
            {"slot":\(transaction.slot),"txSignature":"\(transaction.signature)","eventIndex":\(transaction.eventIndex ?? 0),\
            "txViewingPk":\(base64(transaction.transactionViewingKey)),"salt":\(base64(transaction.salt)),\
            "outputSlots":[\(transaction.outputs.map(output).joined(separator: ","))],"messages":[],\
            "nullifiers":[\(nullifiers)],"proofless":\(transaction.isProofless)}
            """
    }

    static func match(_ deposit: ShieldedTransaction) -> String {
        let output = deposit.outputs.map(output).joined()
        return #"{"slot":\#(deposit.slot),"txSignature":"\#(deposit.signature)","outputSlot":\#(output),"txViewingPk":null,"salt":null}"#
    }

    static func page(_ rows: [String], in field: String, scanned: String, outputTreeID: UInt16? = nil) -> String {
        let tree = outputTreeID.map { #","outputTreeId":\#($0)"# } ?? ""
        return #""result":{"context":{"slot":2},"\#(field)":[\#(rows.joined(separator: ","))],"nextCursor":null,"#
            + #""scannedThrough":"\#(scanned)"\#(tree)}"#
    }

    private static func output(_ output: ShieldedOutput) -> String {
        """
        {"viewTag":"\(Base58.encode(output.viewTag))","outputContext":{"hash":"\(Base58.encode(output.utxoHash))",\
        "treeId":\(output.treeID),"leafIndex":\(output.leafIndex)},"payload":"\(Data(output.payload).base64EncodedString())"}
        """
    }

    private static func base64(_ bytes: [UInt8]?) -> String {
        bytes.map { "\"\(Data($0).base64EncodedString())\"" } ?? "null"
    }
}
