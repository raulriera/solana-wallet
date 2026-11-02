import Foundation

nonisolated enum IndexerReplies {
    static let scannedThrough = "AQ=="

    static func output(viewTag: String, hash: String, treeID: UInt16, leafIndex: UInt64, payload: String) -> String {
        """
        {"viewTag":"\(viewTag)","outputContext":{"hash":"\(hash)","treeId":\(treeID),"leafIndex":\(leafIndex)},\
        "payload":"\(payload)"}
        """
    }

    static func transaction(signature: String, slot: UInt64, eventIndex: UInt16 = 0, viewingKey: String? = nil,
                            salt: String? = nil, outputs: [String] = [], nullifiers: [String] = [],
                            isProofless: Bool = false) -> String {
        let nullifiers = nullifiers.map { "\"\($0)\"" }.joined(separator: ",")
        return """
            {"slot":\(slot),"txSignature":"\(signature)","eventIndex":\(eventIndex),\
            "txViewingPk":\(quoted(viewingKey)),"salt":\(quoted(salt)),\
            "outputSlots":[\(outputs.joined(separator: ","))],"messages":[],\
            "nullifiers":[\(nullifiers)],"proofless":\(isProofless)}
            """
    }

    static func match(signature: String, slot: UInt64, output: String, viewingKey: String? = nil,
                      salt: String? = nil) -> String {
        """
        {"slot":\(slot),"txSignature":"\(signature)","outputSlot":\(output),\
        "txViewingPk":\(quoted(viewingKey)),"salt":\(quoted(salt))}
        """
    }

    static func page(_ rows: [String], in field: String, next: String? = nil,
                     scannedThrough: String? = IndexerReplies.scannedThrough, outputTreeID: UInt16? = nil) -> String {
        var fields = [#""context":{"blockTime":1,"slot":2}"#, #""\#(field)":[\#(rows.joined(separator: ","))]"#]
        if let next {
            fields.append(#""nextCursor":"\#(next)""#)
        } else {
            fields.append(#""nextCursor":null"#)
            if let scannedThrough { fields.append(#""scannedThrough":"\#(scannedThrough)""#) }
        }
        if let outputTreeID { fields.append(#""outputTreeId":\#(outputTreeID)"#) }
        return "{\(fields.joined(separator: ","))}"
    }

    private static func quoted(_ text: String?) -> String {
        text.map { "\"\($0)\"" } ?? "null"
    }
}
