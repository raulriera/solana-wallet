import ModularArithmetic
import RPC

/// The payload of a proofless deposit's output, with the UTXO in the clear.
struct ProoflessOutput: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// An error that rejects a payload as a proofless output.
    enum ValidationError: Error, Equatable {
        case invalidLength
        case unsupportedEncoding
        case unsupportedScheme
        /// The owner hash or the blinding isn't a canonical field element.
        case invalidField
        /// The output carries a data hash, UTXO data, or a ring.
        case unsupportedData
    }

    /// The length of the encoding tag and the declared length, in bytes.
    private static let headerLength = 5

    private static let prooflessScheme: UInt8 = 0

    /// The number of absent options before the memo.
    private static let absentOptions = 5

    /// The UTXO's owner hash.
    let owner: Poseidon.Element

    let blinding: Poseidon.Element

    /// The asset's 32-byte mint address, all zeros for SOL.
    let mint: [UInt8]

    /// The amount, in the asset's smallest unit.
    let amount: UInt64

    var description: String { "ProoflessOutput" }

    var debugDescription: String { description }

    var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Creates an output by decoding a published payload.
    ///
    /// - Parameter payload: The output's data slot.
    /// - Throws: ``ValidationError/invalidLength`` if a length doesn't fit,
    ///   ``ValidationError/unsupportedEncoding`` or ``ValidationError/unsupportedScheme`` for another encoding
    ///   or scheme, ``ValidationError/invalidField`` for a non-canonical owner hash or blinding, or
    ///   ``ValidationError/unsupportedData`` if an option before the memo is present.
    init(decoding payload: [UInt8]) throws {
        guard payload.count > Self.headerLength else { throw ValidationError.invalidLength }
        guard payload[0] == ShieldedOutput.Encoding.plaintext.rawValue else { throw ValidationError.unsupportedEncoding }
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
