import Foundation
import Testing

nonisolated enum MerkleProofReplies {
    static func requestedLeaves(in request: URLRequest) throws -> (tree: String, leaves: [String]) {
        let params = try #require(try requestBody(request)["params"] as? [String: Any])
        return (try #require(params["treeAccount"] as? String), try #require(params["leaves"] as? [String]))
    }

    static func proof(leaf: String, tree: String, treeType: Int = 1, path: [String], leafIndex: Int, root: String,
                      rootIndex: Int) -> String {
        let path = path.map { "\"\($0)\"" }.joined(separator: ",")
        return """
            {"leaf":"\(leaf)","merkleContext":{"treeType":\(treeType),"tree":"\(tree)"},"path":[\(path)],\
            "leafIndex":\(leafIndex),"root":"\(root)","rootSeq":1,"rootIndex":\(rootIndex)}
            """
    }

    static func result(_ proofs: [String]) -> String {
        #"{"context":{"blockTime":1,"slot":2},"proofs":[\#(proofs.joined(separator: ","))]}"#
    }
}
