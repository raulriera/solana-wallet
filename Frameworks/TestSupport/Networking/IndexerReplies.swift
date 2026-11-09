import Foundation

nonisolated enum IndexerReplies {
    static let contextSlot: UInt64 = 2

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
                     contextSlot: UInt64 = IndexerReplies.contextSlot, outputTreeID: UInt16? = nil) -> String {
        var fields = [#""context":{"blockTime":1,"slot":\#(contextSlot)}"#,
                      #""data":[\#(transactions(of: rows, in: field).joined(separator: ","))]"#,
                      #""paginationToken":\#(quoted(next))"#]
        if let outputTreeID { fields.append(#""outputTreeId":\#(outputTreeID)"#) }
        return "{\(fields.joined(separator: ","))}"
    }

    private static func transactions(of rows: [String], in field: String) -> [String] {
        var groups: [(slot: Substring, signature: Substring, rows: [String])] = []
        for row in rows {
            let slot = row.firstMatch(of: /"slot":(\d+)/)?.output.1 ?? ""
            let signature = row.firstMatch(of: /"txSignature":"([^"]+)"/)?.output.1 ?? ""
            if let last = groups.last, last.signature == signature {
                groups[groups.count - 1].rows.append(row)
            } else {
                groups.append((slot, signature, [row]))
            }
        }
        return groups.map { group in
            let rows = group.rows.joined(separator: ",")
            return #"{"slot":\#(group.slot),"signature":"\#(group.signature)","\#(field)":[\#(rows)]}"#
        }
    }

    private static func quoted(_ text: String?) -> String {
        text.map { "\"\($0)\"" } ?? "null"
    }
}
