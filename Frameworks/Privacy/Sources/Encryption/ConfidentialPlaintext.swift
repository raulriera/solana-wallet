import ModularArithmetic

/// The plaintext note of a confidential output, with its UTXO's asset, amount, and blinding.
struct ConfidentialPlaintext: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The assets that confidential outputs carry, with their asset IDs as raw values.
    enum Asset: UInt64, Sendable {
        case sol = 1

        var mint: [UInt8] {
            switch self {
            case .sol: [UInt8](repeating: 0, count: 32)
            }
        }
    }

    /// An error that rejects bytes as a note.
    enum ValidationError: Error, Equatable {
        case invalidLength
        case unsupportedAsset
        case nonCanonicalBlinding
        case unsupportedRingProgram
        /// The note carries data records.
        case unsupportedData
    }

    /// The number of bytes in an encoded note.
    static let length = 50

    private static let amountOffset = 8

    private static let blindingRange = 16..<48

    /// The offset of the ring program's option tag.
    private static let ringProgramOffset = 48

    /// The offset of the data record count.
    private static let dataOffset = 49

    let asset: Asset

    /// The amount, in the asset's smallest unit.
    let amount: UInt64

    let blinding: Poseidon.Element

    var description: String { "ConfidentialPlaintext" }

    var debugDescription: String { description }

    var customMirror: Mirror { Mirror(self, children: [:]) }

    var encoded: [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(Self.length)
        bytes.appendLittleEndian(asset.rawValue)
        bytes.appendLittleEndian(amount)
        bytes += blinding.bigEndianBytes
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

    /// Creates a note by decoding its bytes.
    ///
    /// - Parameter bytes: The 50-byte encoding.
    /// - Throws: ``ValidationError/invalidLength`` for another length, ``ValidationError/unsupportedAsset``
    ///   for an asset other than SOL, ``ValidationError/nonCanonicalBlinding`` for a blinding at or above r,
    ///   ``ValidationError/unsupportedRingProgram`` for a ring program, or ``ValidationError/unsupportedData``
    ///   for data records.
    init(decoding bytes: [UInt8]) throws {
        guard bytes.count >= Self.length else { throw ValidationError.invalidLength }
        guard let asset = Asset(rawValue: bytes.littleEndian(at: 0)) else { throw ValidationError.unsupportedAsset }
        guard let blinding = Poseidon.Element(bigEndianBytes: Array(bytes[Self.blindingRange])) else {
            throw ValidationError.nonCanonicalBlinding
        }
        guard bytes[Self.ringProgramOffset] == 0 else { throw ValidationError.unsupportedRingProgram }
        guard bytes[Self.dataOffset] == 0 else { throw ValidationError.unsupportedData }
        guard bytes.count == Self.length else { throw ValidationError.invalidLength }
        self.init(asset: asset, amount: bytes.littleEndian(at: Self.amountOffset), blinding: blinding)
    }
}
