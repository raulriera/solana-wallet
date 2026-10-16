import Encoding
import Foundation
import RPC

/// Indexer JSON for shielded transactions, as Helius's Solana Rings indexer encodes them.
///
/// Confidential transactions are rows of the transaction streams; proofless deposits are rows of
/// the encrypted-output stream. Hashes, tags, nullifiers, and addresses are base 58; keys, salts,
/// and payloads are base 64.
enum IndexerResponses {
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
    /// - Returns: The member, for ``reply(to:payload:status:headers:id:)``.
    static func page(_ rows: [String], in field: String, scanned: String) -> String {
        #""result":{"context":{"slot":2},"\#(field)":[\#(rows.joined(separator: ","))],"nextCursor":null,"scannedThrough":"\#(scanned)"}"#
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
