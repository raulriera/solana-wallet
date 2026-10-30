import Encoding

/// A proof with the tree account that its context names.
struct TreeProof<Proof: Sendable>: Sendable {
    /// The tree account's base-58 address.
    let tree: String
    let proof: Proof
}

/// The strict decoding of a `getMerkleProofs` result, one proof per requested leaf in request order.
struct MerkleProofList: Decodable, Sendable {
    let proofs: [TreeProof<MerkleProof>]

    init(from decoder: any Decoder) throws {
        proofs = try decoder.container(keyedBy: ProofKey.self).decode([Entry].self, forKey: .proofs).map(\.value)
    }

    /// One decoded proof.
    private struct Entry: Decodable {
        let value: TreeProof<MerkleProof>

        init(from decoder: any Decoder) throws {
            let entry = try decoder.container(keyedBy: ProofKey.self)
            value = TreeProof(tree: try entry.decodeTree(type: 1), proof: try MerkleProof(
                leaf: try entry.decode(IndexedHash.self, forKey: .leaf).bytes,
                path: try entry.decodePath(count: MerkleProof.height),
                leafIndex: try entry.decode(UInt64.self, forKey: .leafIndex),
                root: try entry.decode(IndexedHash.self, forKey: .root).bytes,
                rootIndex: try entry.decode(UInt16.self, forKey: .rootIndex)
            ))
        }
    }
}

/// The strict decoding of a `getNonInclusionProofs` result, one proof per requested nullifier in request order.
struct NonInclusionProofList: Decodable, Sendable {
    let proofs: [TreeProof<NonInclusionProof>]

    init(from decoder: any Decoder) throws {
        proofs = try decoder.container(keyedBy: ProofKey.self).decode([Entry].self, forKey: .proofs).map(\.value)
    }

    /// One decoded proof.
    private struct Entry: Decodable {
        let value: TreeProof<NonInclusionProof>

        init(from decoder: any Decoder) throws {
            let entry = try decoder.container(keyedBy: ProofKey.self)
            value = TreeProof(tree: try entry.decodeTree(type: 2), proof: try NonInclusionProof(
                nullifier: try entry.decode(IndexedHash.self, forKey: .leaf).bytes,
                lowElement: try entry.decode(IndexedHash.self, forKey: .lowElement).bytes,
                lowElementIndex: try entry.decode(UInt64.self, forKey: .lowElementIndex),
                highElement: try entry.decode(IndexedHash.self, forKey: .highElement).bytes,
                path: try entry.decodePath(count: NonInclusionProof.height),
                root: try entry.decode(IndexedHash.self, forKey: .root).bytes,
                rootIndex: try entry.decode(UInt16.self, forKey: .rootIndex)
            ))
        }
    }
}

/// The field names of indexer proof results.
private enum ProofKey: String, CodingKey {
    case proofs, leaf, merkleContext, treeType, tree, path, leafIndex, root, rootIndex
    case lowElement, lowElementIndex, highElement
}

fileprivate extension KeyedDecodingContainer<ProofKey> {
    /// Decodes a proof's tree account after checking its tree type.
    ///
    /// - Parameter type: The required tree type: 1 for a UTXO tree, 2 for a nullifier tree.
    /// - Returns: The tree account's base-58 address, as received.
    /// - Throws: A decoding error for a missing field, another tree type, or an address that isn't 32 bytes.
    func decodeTree(type: Int) throws -> String {
        let context = try nestedContainer(keyedBy: ProofKey.self, forKey: .merkleContext)
        guard try context.decode(Int.self, forKey: .treeType) == type else {
            throw DecodingError.dataCorruptedError(forKey: .treeType, in: context, debugDescription: "Another tree type.")
        }
        let tree = try context.decode(String.self, forKey: .tree)
        guard Base58.decode(tree, byteCount: 32) != nil else {
            throw DecodingError.dataCorruptedError(forKey: .tree, in: context, debugDescription: "Invalid address.")
        }
        return tree
    }

    /// Decodes a path of base-58 hashes of a fixed length.
    ///
    /// - Parameter count: The required number of hashes.
    /// - Returns: Each sibling's 32 bytes, in order.
    /// - Throws: A decoding error for a missing field, a hash that isn't 32 bytes, or another length.
    func decodePath(count: Int) throws -> [[UInt8]] {
        let path = try decode([IndexedHash].self, forKey: .path).map(\.bytes)
        guard path.count == count else {
            throw DecodingError.dataCorruptedError(forKey: .path, in: self, debugDescription: "Path of another length.")
        }
        return path
    }
}
