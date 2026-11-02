/// The strict decoding of a prover's JSON indexed transfer proof.
struct IndexedTransferProofResponse: Decodable, Sendable {
    let proof: IndexedTransferProof

    init(from decoder: any Decoder) throws {
        let body = try decoder.container(keyedBy: CodingKeys.self)
        let resolution = try body.decode(ResolutionBody.self, forKey: .resolution)
        proof = IndexedTransferProof(
            proof: try TransferProofResponse(from: decoder).proof,
            resolution: ProofResolution(
                trees: resolution.trees.map {
                    ProofResolution.Tree(id: $0.id, address: $0.tree.bytes, utxoRoot: $0.utxoRoot.bytes,
                                         nullifierRoot: $0.nullifierRoot.bytes, utxoRootIndex: $0.utxoRootIndex,
                                         nullifierRootIndex: $0.nullifierRootIndex)
                },
                publicInputHash: resolution.publicInputHash.bytes
            )
        )
    }

    /// The field of a proof's resolution.
    private enum CodingKeys: String, CodingKey {
        case resolution
    }
}

/// A resolution's trees and public input hash.
private struct ResolutionBody: Decodable {
    let trees: [ResolvedTreeBody]
    let publicInputHash: HexField
}

/// A resolved tree with a base-58 address, 16-bit ID and root indexes, and 32-byte roots.
private struct ResolvedTreeBody: Decodable {
    let tree: IndexedHash
    let id: UInt16
    let utxoRoot: HexField
    let nullifierRoot: HexField
    let utxoRootIndex: UInt16
    let nullifierRootIndex: UInt16
}

/// A 32-byte value as `0x` and 1 to 64 lowercase hexadecimal digits.
private struct HexField: Decodable {
    /// The value's 32 big-endian bytes.
    let bytes: [UInt8]

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard (1...64).contains(text.utf8.count - 2), let bytes = FieldHex.decode(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid field element.")
        }
        self.bytes = bytes
    }
}
