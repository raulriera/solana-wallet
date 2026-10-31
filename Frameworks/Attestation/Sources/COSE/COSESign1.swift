import CryptoKit
import Encoding

/// A COSE_Sign1 message signed with ES384, RFC 9052.
struct COSESign1: Sendable {
    /// An error that rejects bytes as an ES384 COSE_Sign1 message.
    enum ValidationError: Error, Equatable {
        case malformed
        case unsupportedAlgorithm
    }

    private static let tag: UInt64 = 18

    private static let algorithmLabel = CBOR.Key.integer(1)

    /// The COSE identifier of ECDSA with SHA-384.
    private static let es384 = CBOR.integer(-35)

    /// The encoded protected header.
    let protectedHeader: [UInt8]

    let payload: [UInt8]

    let signature: P384.Signing.ECDSASignature

    /// Decodes a message, with or without its leading tag.
    ///
    /// - Parameter bytes: The encoded message.
    /// - Throws: ``ValidationError/malformed`` for a structure other than COSE_Sign1's or a signature other than
    ///   96 bytes, ``ValidationError/unsupportedAlgorithm`` for a protected header that doesn't name ES384, or a
    ///   `CBOR.ValidationError` for a message or protected header outside the strict CBOR subset.
    init(decoding bytes: [UInt8]) throws {
        guard case .array(let fields) = try CBOR(decoding: bytes, allowingLeadingTag: Self.tag), fields.count == 4,
            case .bytes(let protectedHeader) = fields[0],
            case .map = fields[1],
            case .bytes(let payload) = fields[2],
            case .bytes(let signature) = fields[3],
            case .map(let header) = try CBOR(decoding: protectedHeader)
        else { throw ValidationError.malformed }
        guard header[Self.algorithmLabel] == Self.es384 else { throw ValidationError.unsupportedAlgorithm }
        guard let signature = try? P384.Signing.ECDSASignature(rawRepresentation: signature) else {
            throw ValidationError.malformed
        }
        self.protectedHeader = protectedHeader
        self.payload = payload
        self.signature = signature
    }

    /// Reports whether a key signed the message.
    ///
    /// - Parameter key: The key to check the signature with.
    /// - Returns: `true` when the signature verifies over the message's `Signature1` structure with no external
    ///   data.
    func isValidSignature(from key: P384.Signing.PublicKey) -> Bool {
        key.isValidSignature(signature, for: Self.signatureStructure(protectedHeader: protectedHeader, payload: payload))
    }

    /// Encodes the `Signature1` structure that a message's signature covers, with no external data.
    ///
    /// - Parameters:
    ///   - protectedHeader: The encoded protected header.
    ///   - payload: The signed content.
    /// - Returns: The encoded structure.
    static func signatureStructure(protectedHeader: [UInt8], payload: [UInt8]) -> [UInt8] {
        CBOR.array([.text("Signature1"), .bytes(protectedHeader), .bytes([]), .bytes(payload)]).encoded
    }
}
