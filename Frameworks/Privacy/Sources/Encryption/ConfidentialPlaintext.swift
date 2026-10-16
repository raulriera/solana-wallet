import ModularArithmetic

/// The note of a confidential default-ring output: what its recipient needs to rebuild the UTXO.
///
/// The 50-byte encoding, as zolana's `encodeConfidential` writes it, is the asset ID and the amount
/// as little-endian 64-bit integers, the blinding as a canonical 32-byte big-endian field element,
/// a zero byte for no ring program, and a zero byte for no data records. The note leaves out the
/// owner hash and the tree ID, which the recipient supplies. Peer-to-peer transfers in the default
/// ring carry no ring program or data, and only SOL is supported, so decoding rejects everything
/// else. Descriptions and reflection omit the amount and the blinding.
struct ConfidentialPlaintext: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The assets that confidential outputs carry, by their IDs in Solana Rings' asset registry.
    ///
    /// This is the one mapping between asset IDs and mints. SOL's asset ID is 1; tokens aren't
    /// supported yet.
    enum Asset: UInt64, Sendable {
        /// SOL, whose mint is 32 zero bytes.
        case sol = 1

        /// The asset's 32-byte mint address, which UTXO hashes commit to.
        var mint: [UInt8] {
            switch self {
            case .sol: [UInt8](repeating: 0, count: 32)
            }
        }
    }

    /// Bytes that aren't a supported note.
    enum ValidationError: Error, Equatable {
        /// A note has exactly 50 bytes.
        case invalidLength
        /// The note's asset ID isn't SOL's.
        case unsupportedAsset
        /// The blinding isn't a canonical field element, below r.
        case nonCanonicalBlinding
        /// The note's ring program isn't None, the default ring's.
        case unsupportedRingProgram
        /// The note carries data records.
        case unsupportedData
    }

    /// The number of bytes in an encoded note.
    static let length = 50

    /// The offset of the amount, after the asset ID.
    private static let amountOffset = 8

    /// The range of the blinding, after the amount.
    private static let blindingRange = 16..<48

    /// The offset of the ring program's option tag, after the blinding.
    private static let ringProgramOffset = 48

    /// The offset of the data record count, after the ring program's option tag.
    private static let dataOffset = 49

    /// The asset.
    let asset: Asset

    /// The amount, in the asset's smallest unit.
    let amount: UInt64

    /// The UTXO's blinding, such as a transact output's blinding.
    let blinding: Poseidon.Element

    /// A description that omits the amount and the blinding.
    var description: String { "ConfidentialPlaintext" }

    /// A debugging description that omits the amount and the blinding.
    var debugDescription: String { description }

    /// A reflection view that omits the amount and the blinding.
    var customMirror: Mirror { Mirror(self, children: [:]) }

    /// The 50-byte encoding.
    var encoded: [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(Self.length)
        bytes.appendLittleEndian(asset.rawValue)
        bytes.appendLittleEndian(amount)
        bytes += blinding.bigEndianBytes
        // No ring program and no data records.
        bytes += [0, 0]
        return bytes
    }

    /// Creates a note.
    ///
    /// - Parameters:
    ///   - asset: The asset.
    ///   - amount: The amount, in the asset's smallest unit.
    ///   - blinding: The UTXO's blinding.
    init(asset: Asset, amount: UInt64, blinding: Poseidon.Element) {
        self.asset = asset
        self.amount = amount
        self.blinding = blinding
    }

    /// Decodes a note.
    ///
    /// - Parameter bytes: The 50-byte encoding.
    /// - Throws: ``ValidationError/invalidLength`` for fewer than 50 bytes, or for more without a
    ///   ring program or data records,
    ///   ``ValidationError/unsupportedAsset`` for an asset ID other than SOL's,
    ///   ``ValidationError/nonCanonicalBlinding`` for a blinding at or above r,
    ///   ``ValidationError/unsupportedRingProgram`` for a ring program, or
    ///   ``ValidationError/unsupportedData`` for data records.
    init(decoding bytes: [UInt8]) throws {
        guard bytes.count >= Self.length else { throw ValidationError.invalidLength }
        guard let asset = Asset(rawValue: bytes.littleEndian(at: 0)) else { throw ValidationError.unsupportedAsset }
        guard let blinding = Poseidon.Element(bigEndianBytes: Array(bytes[Self.blindingRange])) else {
            throw ValidationError.nonCanonicalBlinding
        }
        guard bytes[Self.ringProgramOffset] == 0 else { throw ValidationError.unsupportedRingProgram }
        guard bytes[Self.dataOffset] == 0 else { throw ValidationError.unsupportedData }
        // A ring program or data records would follow; anything else is trailing.
        guard bytes.count == Self.length else { throw ValidationError.invalidLength }
        self.init(asset: asset, amount: bytes.littleEndian(at: Self.amountOffset), blinding: blinding)
    }
}
