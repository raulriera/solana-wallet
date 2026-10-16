import ModularArithmetic

/// The payload of a proofless deposit's output, which publishes the UTXO in the clear.
///
/// The shielded-pool program writes zolana's `OutputDataEncoding::Plaintext`: the encoding tag 0,
/// the little-endian 32-bit length of the rest, the proofless scheme 0, and the Borsh
/// `ProoflessOutput`: the owner hash, the blinding, the mint, the amount as a little-endian 64-bit
/// integer, five absent options (data hash, UTXO data, ring program, ring data hash, ring data),
/// and an optional memo. The program derives the blinding from the tree and the leaf index, and
/// the memo commits to nothing. Descriptions and reflection omit the values.
struct ProoflessOutput: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// A payload that isn't a supported proofless output.
    enum ValidationError: Error, Equatable {
        /// The payload or its declared length doesn't fit a proofless output.
        case invalidLength
        /// The encoding tag isn't plaintext's 0.
        case unsupportedEncoding
        /// The scheme isn't the proofless scheme 0.
        case unsupportedScheme
        /// The owner hash or the blinding isn't a canonical field element.
        case invalidField
        /// The output carries a data hash, UTXO data, or a ring, which default-ring deposits don't.
        case unsupportedData
    }

    /// The length of the encoding tag and the declared length.
    private static let headerLength = 5

    /// The plaintext encoding tag.
    private static let plaintextEncoding: UInt8 = 0

    /// The proofless scheme.
    private static let prooflessScheme: UInt8 = 0

    /// The number of options before the memo, which a default-ring deposit leaves absent.
    private static let absentOptions = 5

    /// The owner hash of the UTXO.
    let owner: Poseidon.Element

    /// The UTXO's blinding.
    let blinding: Poseidon.Element

    /// The asset's 32-byte mint address; SOL's is 32 zero bytes.
    let mint: [UInt8]

    /// The amount, in the asset's smallest unit.
    let amount: UInt64

    /// A description that omits the values.
    var description: String { "ProoflessOutput" }

    /// A debugging description that omits the values.
    var debugDescription: String { description }

    /// A reflection view that omits the values.
    var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Decodes a published payload.
    ///
    /// - Parameter payload: The output's data slot.
    /// - Throws: ``ValidationError/invalidLength`` if the payload, its declared length, or its memo
    ///   doesn't fit, ``ValidationError/unsupportedEncoding`` or
    ///   ``ValidationError/unsupportedScheme`` for another encoding or scheme,
    ///   ``ValidationError/invalidField`` for a non-canonical owner hash or blinding, or
    ///   ``ValidationError/unsupportedData`` if an option before the memo is present.
    init(decoding payload: [UInt8]) throws {
        guard payload.count > Self.headerLength else { throw ValidationError.invalidLength }
        guard payload[0] == Self.plaintextEncoding else { throw ValidationError.unsupportedEncoding }
        let declaredLength: UInt32 = payload.littleEndian(at: 1)
        guard Int(declaredLength) == payload.count - Self.headerLength else { throw ValidationError.invalidLength }
        guard payload[Self.headerLength] == Self.prooflessScheme else { throw ValidationError.unsupportedScheme }
        let body = Array(payload[(Self.headerLength + 1)...])
        let optionsStart = 3 * 32 + 8
        guard body.count > optionsStart + Self.absentOptions else { throw ValidationError.invalidLength }
        guard let owner = Poseidon.Element(bigEndianBytes: Array(body[0..<32])),
              let blinding = Poseidon.Element(bigEndianBytes: Array(body[32..<64])) else { throw ValidationError.invalidField }
        guard body[optionsStart..<optionsStart + Self.absentOptions].allSatisfy({ $0 == 0 }) else { throw ValidationError.unsupportedData }
        let memo = Array(body[(optionsStart + Self.absentOptions)...])
        switch memo.first {
        case 0 where memo.count == 1:
            break
        case 1 where memo.count >= 5 && Int(memo.littleEndian(at: 1) as UInt32) == memo.count - 5:
            break
        default:
            throw ValidationError.invalidLength
        }
        self.owner = owner
        self.blinding = blinding
        mint = Array(body[64..<96])
        amount = body.littleEndian(at: 96)
    }
}
