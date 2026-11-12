import ModularArithmetic
import Redaction

/// The plaintext note of a confidential output, with its UTXO's asset, amount, and blinding.
struct ConfidentialPlaintext: Sendable, Equatable, Redacted {
    /// The assets that private balances hold, with their pool asset IDs as raw values.
    enum Asset: UInt64, Sendable, CaseIterable, Codable {
        case sol = 1
        /// Mainnet USDC.
        case usdc = 3
        /// Mainnet USDT.
        case usdt = 19
        /// Devnet USDC.
        case devnetUSDC = 59

        /// The mint's 32 bytes, which are all zero for SOL.
        var mint: [UInt8] {
            switch self {
            case .sol: [UInt8](repeating: 0, count: 32)
            case .usdc: [
                198, 250, 122, 243, 190, 219, 173, 58, 61, 101, 243, 106, 171, 201, 116, 49,
                177, 187, 228, 194, 210, 246, 224, 228, 124, 166, 2, 3, 69, 47, 93, 97,
            ]
            case .usdt: [
                206, 1, 14, 96, 175, 237, 178, 39, 23, 189, 99, 25, 47, 84, 20, 90,
                63, 150, 90, 51, 187, 130, 210, 199, 2, 158, 178, 206, 30, 32, 130, 100,
            ]
            case .devnetUSDC: [
                59, 68, 44, 179, 145, 33, 87, 241, 58, 147, 61, 1, 52, 40, 45, 3,
                43, 95, 254, 205, 1, 162, 219, 241, 183, 121, 6, 8, 223, 0, 46, 167,
            ]
            }
        }

        /// Returns the asset of a mint.
        ///
        /// - Parameter mint: The mint's 32 bytes.
        /// - Returns: The asset, or `nil` for a mint that private balances don't hold.
        init?(mint: [UInt8]) {
            guard let asset = Self.allCases.first(where: { $0.mint == mint }) else { return nil }
            self = asset
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
    ///   for an asset that private balances don't hold, ``ValidationError/nonCanonicalBlinding`` for a blinding at or above r,
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
