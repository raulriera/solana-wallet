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
        let owner = try ShieldedPool.program.value
        let account = #"{"owner":"\#(owner)","lamports":1,"executable":false,"data":["AAAAAAAAAAA=","base64"]}"#
        let accounts = addresses.map { queued.contains($0) ? account : "null" }.joined(separator: ",")
        return try reply(to: request, payload: #""result":{"context":{"slot":1},"value":[\#(accounts)]}"#)
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

    static func page(_ rows: [String], in field: String, next: String? = nil, scanned: String,
                     outputTreeID: UInt16? = nil) -> String {
        let tree = outputTreeID.map { #","outputTreeId":\#($0)"# } ?? ""
        let end = next.map { #""nextCursor":"\#($0)""# } ?? #""nextCursor":null,"scannedThrough":"\#(scanned)""#
        return #""result":{"context":{"slot":2},"\#(field)":[\#(rows.joined(separator: ","))],\#(end)\#(tree)}"#
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
