import Encoding

/// A proof that an indexer returned, with the tree account that its context names.
struct TreeProof<Proof: Sendable>: Sendable {
    /// The tree account's base-58 address.
    let tree: String
    /// The proof.
    let proof: Proof
}

/// The strict decoding of a `getMerkleProofs` result: one proof per requested leaf, in request order.
///
/// Each proof names a UTXO tree, tree type 1, and has a path of 32 base-58 hashes.
struct MerkleProofList: Decodable, Sendable {
    /// The proofs, with their trees.
    let proofs: [TreeProof<MerkleProof>]

    /// Decodes the result and each of its proofs.
    ///
    /// - Parameter decoder: The decoder containing the JSON-RPC result.
    /// - Throws: A decoding error for a missing field, another tree type, a path of another length, a hash that
    ///   isn't 32 bytes of base 58, or an invalid tree address.
    init(from decoder: any Decoder) throws {
        proofs = try decoder.container(keyedBy: ProofKey.self).decode([Entry].self, forKey: .proofs).map(\.value)
    }

    /// One decoded proof.
    private struct Entry: Decodable {
        /// The proof and its tree.
        let value: TreeProof<MerkleProof>

        /// Decodes a proof.
        ///
        /// - Parameter decoder: The decoder containing one proof.
        /// - Throws: A decoding error as ``MerkleProofList/init(from:)`` describes.
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

/// The strict decoding of a `getNonInclusionProofs` result: one proof per requested nullifier, in request order.
///
/// Each proof names a nullifier tree, tree type 2, and has a path of 40 base-58 hashes. The high element's index,
/// which the circuit doesn't read, is ignored.
struct NonInclusionProofList: Decodable, Sendable {
    /// The proofs, with their trees.
    let proofs: [TreeProof<NonInclusionProof>]

    /// Decodes the result and each of its proofs.
    ///
    /// - Parameter decoder: The decoder containing the JSON-RPC result.
    /// - Throws: A decoding error for a missing field, another tree type, a path of another length, a hash that
    ///   isn't 32 bytes of base 58, or an invalid tree address.
    init(from decoder: any Decoder) throws {
        proofs = try decoder.container(keyedBy: ProofKey.self).decode([Entry].self, forKey: .proofs).map(\.value)
    }

    /// One decoded proof.
    private struct Entry: Decodable {
        /// The proof and its tree.
        let value: TreeProof<NonInclusionProof>

        /// Decodes a proof.
        ///
        /// - Parameter decoder: The decoder containing one proof.
        /// - Throws: A decoding error as ``NonInclusionProofList/init(from:)`` describes.
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
    /// Decodes a proof's context: its tree type, which must match, and its tree account.
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
    /// - Parameter count: The tree's height.
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
