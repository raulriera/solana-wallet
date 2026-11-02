nonisolated enum MerkleProofReplies {
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
