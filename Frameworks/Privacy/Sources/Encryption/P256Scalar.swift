import CryptoKit
import Foundation
import ModularArithmetic

/// The reduction of uniform key material to P-256 private keys, zolana's `scalarFromOkm`.
///
/// The key material is a 48-byte big-endian value, reduced modulo the P-256 order n as RFC 9380's
/// `hash_to_field` reduces it; the 128 extra bits keep the result's bias negligible. The value is
/// `high × 2^256 + low`, where `high` is its first 16 bytes and `low` its last 32, so its residue is
/// `low + high × (2^256 mod n)` in ModularArithmetic's P-256 scalar field, and
/// `2^256 mod n = ((2^256 - 1) mod n) + 1`. A zero residue isn't a private key.
enum P256Scalar {
    /// An element of the P-256 scalar field.
    typealias Element = FieldElement<P256ScalarField>

    /// Key material that reduces to no private key.
    enum ValidationError: Error, Equatable {
        /// The key material is a multiple of n, so its residue is zero.
        case zeroScalar
    }

    /// The number of bytes of key material.
    static let keyMaterialLength = 48

    /// The number of leading key-material bytes that the residue weighs by 2^256.
    private static let highLength = 16

    /// 2^256 mod n, the weight of the key material's first 16 bytes.
    private static let highWeight = Element(reducing: [UInt8](repeating: 0xff, count: 32)) + .one

    /// Reduces 48 bytes of key material to a private key.
    ///
    /// The buffers that hold the halves of the key material and the scalar are zeroed before
    /// they're released; the field elements aren't erased.
    ///
    /// - Parameter keyMaterial: Exactly 48 bytes, such as an HKDF output.
    /// - Returns: The private key whose scalar is the key material modulo n.
    /// - Throws: ``ValidationError/zeroScalar`` if the key material is a multiple of n.
    /// - Precondition: `keyMaterial` contains exactly 48 bytes.
    static func privateKey(reducing keyMaterial: some ContiguousBytes) throws -> P256.KeyAgreement.PrivateKey {
        let scalar = residue(of: keyMaterial)
        guard scalar != .zero else { throw ValidationError.zeroScalar }
        var bytes = scalar.bigEndianBytes
        defer { bytes.erase() }
        return try P256.KeyAgreement.PrivateKey(rawRepresentation: bytes)
    }

    /// Reduces 48 bytes of key material modulo n.
    ///
    /// - Parameter keyMaterial: Exactly 48 bytes.
    /// - Returns: `low + high × (2^256 mod n)`, the key material's residue.
    /// - Precondition: `keyMaterial` contains exactly 48 bytes.
    private static func residue(of keyMaterial: some ContiguousBytes) -> Element {
        keyMaterial.withUnsafeBytes { source in
            precondition(source.count == keyMaterialLength, "A P-256 scalar reduces exactly 48 bytes of key material.")
            let high = Element(reducingRightAligned: UnsafeRawBufferPointer(rebasing: source[..<highLength]))
            let low = Element(reducingRightAligned: UnsafeRawBufferPointer(rebasing: source[highLength...]))
            return low + high * highWeight
        }
    }
}
