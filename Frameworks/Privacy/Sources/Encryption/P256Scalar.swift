import CryptoKit
import Foundation
import ModularArithmetic

/// The reduction of uniform key material to P-256 private keys.
enum P256Scalar {
    /// An element of the P-256 scalar field.
    typealias Element = FieldElement<P256ScalarField>

    /// An error that rejects key material as a private key.
    enum ValidationError: Error, Equatable {
        case zeroScalar
    }

    /// The length of the key material, in bytes.
    static let keyMaterialLength = 48

    /// The number of leading key-material bytes that the residue weighs by 2^256.
    private static let highLength = 16

    /// The weight of the key material's leading bytes, 2^256 mod n.
    private static let highWeight = Element(reducing: [UInt8](repeating: 0xff, count: 32)) + .one

    /// Reduces 48 bytes of key material to a private key.
    ///
    /// - Parameter keyMaterial: The 48 bytes of uniform key material.
    /// - Returns: The private key whose scalar is the key material modulo n.
    /// - Throws: ``ValidationError/zeroScalar`` if the key material is a multiple of n.
    static func privateKey(reducing keyMaterial: some ContiguousBytes) throws -> P256.KeyAgreement.PrivateKey {
        let scalar = residue(of: keyMaterial)
        guard scalar != .zero else { throw ValidationError.zeroScalar }
        var bytes = scalar.bigEndianBytes
        defer { bytes.erase() }
        return try P256.KeyAgreement.PrivateKey(rawRepresentation: bytes)
    }

    /// Reduces 48 bytes of key material modulo n.
    ///
    /// - Parameter keyMaterial: The 48 bytes of key material.
    /// - Returns: The key material's residue.
    private static func residue(of keyMaterial: some ContiguousBytes) -> Element {
        keyMaterial.withUnsafeBytes { source in
            precondition(source.count == keyMaterialLength, "A P-256 scalar reduces exactly 48 bytes of key material.")
            let high = Element(reducingRightAligned: UnsafeRawBufferPointer(rebasing: source[..<highLength]))
            let low = Element(reducingRightAligned: UnsafeRawBufferPointer(rebasing: source[highLength...]))
            return low + high * highWeight
        }
    }
}
