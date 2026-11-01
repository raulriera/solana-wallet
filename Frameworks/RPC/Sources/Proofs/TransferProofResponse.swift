import Encoding

/// The strict decoding of a prover's JSON transfer proof.
struct TransferProofResponse: Decodable, Sendable {
    let proof: TransferProof

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
        guard let digestBytes = Hex.decode(digest), digestBytes.count == 32 else {
            throw DecodingError.dataCorruptedError(forKey: .provingKeySha256, in: body, debugDescription: "Invalid digest.")
        }
        proof = TransferProof(
            a: TransferProof.G1Point(x: a[0], y: a[1]),
            b: b.flatMap { $0.flatMap(\.self) },
            c: TransferProof.G1Point(x: c[0], y: c[1]),
            provingKeyDigest: digestBytes
        )
    }

    /// The fields of a proof.
    private enum CodingKeys: String, CodingKey {
        case ar, bs, krs, provingKeySha256, proofCommitment, proofCommitmentPok
    }
}

/// A list of 32-byte words in prover hexadecimal.
private struct HexWords: Decodable {
    let words: [[UInt8]]

    init(from decoder: any Decoder) throws {
        words = try decoder.singleValueContainer().decode([HexWord].self).map(\.bytes)
    }
}

/// One 32-byte word in prover hexadecimal.
private struct HexWord: Decodable {
    /// The word's 32 big-endian bytes.
    let bytes: [UInt8]

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let bytes = FieldHex.decode(try container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid word.")
        }
        self.bytes = bytes
    }
}
