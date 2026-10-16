import Encoding

/// The strict decoding of a prover's JSON proof on the indexed route.
///
/// The body is gnark's proof, `{ar, bs, krs}`, with `provingKeySha256` and `resolution`, which this route
/// requires, and without the commitment that only P-256 proofs carry. Coordinates and roots are `0x` hexadecimal with or without leading zeros.
struct TransferProofResponse: Decodable, Sendable {
    /// The decoded proof.
    let proof: TransferProof

    /// Decodes the proof.
    ///
    /// - Parameter decoder: The decoder containing the response body.
    /// - Throws: A decoding error for a missing field, a wrong count, a value of more than 32 bytes, a digest
    ///   that isn't 64 lowercase hexadecimal digits, or a tree address that isn't 32 bytes of base 58.
    init(from decoder: any Decoder) throws {
        let body = try decoder.container(keyedBy: CodingKeys.self)
        guard !body.contains(.proofCommitment), !body.contains(.proofCommitmentPok) else {
            throw DecodingError.dataCorruptedError(forKey: .proofCommitment, in: body,
                                                   debugDescription: "EdDSA transfer proofs carry no commitment.")
        }
        let a = try body.decode(HexWords.self, forKey: .ar).words
        let b = try body.decode([HexWords].self, forKey: .bs).map(\.words)
        let c = try body.decode(HexWords.self, forKey: .krs).words
        guard a.count == 2, c.count == 2, b.count == 2, b.allSatisfy({ $0.count == 2 }) else {
            throw DecodingError.dataCorruptedError(forKey: .bs, in: body, debugDescription: "Invalid point.")
        }
        let digest = try body.decode(String.self, forKey: .provingKeySha256)
        guard digest.utf8.count == 64, digest == digest.lowercased(), let digestBytes = FieldHex.decode("0x" + digest) else {
            throw DecodingError.dataCorruptedError(forKey: .provingKeySha256, in: body, debugDescription: "Invalid digest.")
        }
        let resolution = try body.nestedContainer(keyedBy: CodingKeys.self, forKey: .resolution)
        proof = TransferProof(
            a: TransferProof.G1Point(x: a[0], y: a[1]),
            b: b.flatMap { $0.flatMap(\.self) },
            c: TransferProof.G1Point(x: c[0], y: c[1]),
            provingKeyDigest: digestBytes,
            resolution: TransferProof.Resolution(
                trees: try resolution.decode([ResolvedTreeBody].self, forKey: .trees).map(\.value),
                publicInputHash: try resolution.decode(HexWord.self, forKey: .publicInputHash).bytes
            )
        )
    }

    /// The fields of a proof and its resolution.
    private enum CodingKeys: String, CodingKey {
        case ar, bs, krs, provingKeySha256, resolution, trees, publicInputHash, proofCommitment, proofCommitmentPok
    }
}

/// The strict decoding of one resolved tree.
private struct ResolvedTreeBody: Decodable {
    /// The decoded tree.
    let value: TransferProof.ResolvedTree

    /// Decodes a tree.
    ///
    /// - Parameter decoder: The decoder containing one tree.
    /// - Throws: A decoding error for a missing field, an invalid address, or an invalid root.
    init(from decoder: any Decoder) throws {
        let tree = try decoder.container(keyedBy: CodingKeys.self)
        let address = try tree.decode(String.self, forKey: .tree)
        guard Base58.decode(address, byteCount: 32) != nil else {
            throw DecodingError.dataCorruptedError(forKey: .tree, in: tree, debugDescription: "Invalid address.")
        }
        value = TransferProof.ResolvedTree(
            address: address,
            id: try tree.decode(UInt16.self, forKey: .id),
            utxoRoot: try tree.decode(HexWord.self, forKey: .utxoRoot).bytes,
            nullifierRoot: try tree.decode(HexWord.self, forKey: .nullifierRoot).bytes,
            utxoRootIndex: try tree.decode(UInt16.self, forKey: .utxoRootIndex),
            nullifierRootIndex: try tree.decode(UInt16.self, forKey: .nullifierRootIndex)
        )
    }

    /// The fields of a resolved tree.
    private enum CodingKeys: String, CodingKey {
        case tree, id, utxoRoot, nullifierRoot, utxoRootIndex, nullifierRootIndex
    }
}

/// A list of 32-byte words in prover hexadecimal.
private struct HexWords: Decodable {
    /// The words' bytes.
    let words: [[UInt8]]

    /// Decodes a list of words.
    ///
    /// - Parameter decoder: The decoder containing the list.
    /// - Throws: A decoding error for a word that isn't valid or exceeds 32 bytes.
    init(from decoder: any Decoder) throws {
        words = try decoder.singleValueContainer().decode([HexWord].self).map(\.bytes)
    }
}

/// One 32-byte word in prover hexadecimal.
private struct HexWord: Decodable {
    /// The word's 32 big-endian bytes.
    let bytes: [UInt8]

    /// Decodes a word with or without leading zeros.
    ///
    /// - Parameter decoder: The decoder containing the text.
    /// - Throws: A decoding error for text that isn't `0x` and hexadecimal digits, or a value over 32 bytes.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let bytes = FieldHex.decode(try container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid word.")
        }
        self.bytes = bytes
    }
}
