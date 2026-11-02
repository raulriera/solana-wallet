/// The strict decoding of a `getMerkleProofs` result, one proof per requested leaf in request order.
struct MerkleProofList: Decodable, Sendable {
    /// A proof with the tree account that its context names.
    struct Entry: Decodable, Sendable {
        /// The tree type of a UTXO tree.
        private static let utxoTreeType: UInt16 = 1

        /// The tree account's 32 bytes.
        let tree: [UInt8]
        let proof: MerkleProof

        init(from decoder: any Decoder) throws {
            let entry = try decoder.container(keyedBy: ProofKey.self)
            let context = try entry.nestedContainer(keyedBy: ProofKey.self, forKey: .merkleContext)
            guard try context.decode(UInt16.self, forKey: .treeType) == Self.utxoTreeType else {
                throw DecodingError.dataCorruptedError(forKey: .treeType, in: context, debugDescription: "Another tree type.")
            }
            tree = try context.decode(IndexedHash.self, forKey: .tree).bytes
            let path = try entry.decode([IndexedHash].self, forKey: .path).map(\.bytes)
            guard path.count == MerkleProof.height else {
                throw DecodingError.dataCorruptedError(forKey: .path, in: entry, debugDescription: "Path of another height.")
            }
            proof = MerkleProof(
                leaf: try entry.decode(IndexedHash.self, forKey: .leaf).bytes,
                path: path,
                leafIndex: try entry.decode(UInt64.self, forKey: .leafIndex),
                root: try entry.decode(IndexedHash.self, forKey: .root).bytes,
                rootIndex: try entry.decode(UInt16.self, forKey: .rootIndex)
            )
        }
    }

    let proofs: [Entry]
}

/// The field names of a Merkle proof.
private enum ProofKey: String, CodingKey {
    case leaf, merkleContext, treeType, tree, path, leafIndex, root, rootIndex
}
