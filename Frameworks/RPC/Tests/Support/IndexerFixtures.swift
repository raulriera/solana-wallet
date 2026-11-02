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

    static func output(tag: UInt8, hash: UInt8, leafIndex: Int, payload: String = "AQID") -> String {
        """
        {"viewTag":"\(Self.hash(tag))","outputContext":{"hash":"\(Self.hash(hash))",\
        "tree":"\(Self.hash(9))","treeId":0,"leafIndex":\(leafIndex)},"payload":"\(payload)"}
        """
    }

    static func transaction(signature: UInt8, slot: Int, eventIndex: Int = 0, proofless: Bool = false,
                            outputs: [String] = [], nullifiers: [UInt8] = []) -> String {
        let keys = proofless ? #""txViewingPk":null,"salt":null"# : #""txViewingPk":"\#(viewingKey)","salt":"\#(salt)""#
        return """
            {"slot":\(slot),"txSignature":"\(Self.signature(signature))","eventIndex":\(eventIndex),\(keys),\
            "outputSlots":[\(outputs.joined(separator: ","))],"messages":[],\
            "nullifiers":[\(nullifiers.map { "\"\(hash($0))\"" }.joined(separator: ","))],"proofless":\(proofless)}
            """
    }

    static func match(signature: UInt8, slot: Int, output: String, keyed: Bool = false) -> String {
        let keys = keyed ? #""txViewingPk":"\#(viewingKey)","salt":"\#(salt)""# : #""txViewingPk":null,"salt":null"#
        return #"{"slot":\#(slot),"txSignature":"\#(Self.signature(signature))","outputSlot":\#(output),\#(keys)}"#
    }

    static func page(_ items: [String] = [], in rows: String = "transactions", next: String? = nil,
                     scanned: String? = nil, outputTreeID: Int? = nil) -> String {
        var fields = [#""context":{"blockTime":1,"slot":2}"#, #""\#(rows)":[\#(items.joined(separator: ","))]"#,
                      #""nextCursor":\#(next.map { "\"\($0)\"" } ?? "null")"#]
        if let scanned { fields.append(#""scannedThrough":"\#(scanned)""#) }
        if let outputTreeID { fields.append(#""outputTreeId":\#(outputTreeID)"#) }
        return #""result":{\#(fields.joined(separator: ","))}"#
    }

    static func call(_ request: URLRequest) throws -> (route: String, params: [String: Any]) {
        let route = try #require(request.url?.lastPathComponent)
        let params = try #require(try requestBody(request)["params"] as? [String: Any])
        return (route, params)
    }
}
