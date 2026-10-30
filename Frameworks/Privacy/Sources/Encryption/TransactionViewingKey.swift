import CryptoKit
import Foundation
import ModularArithmetic

/// The per-transaction viewing key that seals the notes of a transaction's outputs.
enum TransactionViewingKey {
    /// The compressed P-256 point that each account's view root derives from.
    private static let viewRootPoint: [UInt8] = [
        0x03, 0x0e, 0x4d, 0xf9, 0x46, 0xbc, 0xe1, 0x4b, 0x95, 0x29, 0x2f,
        0x13, 0xe1, 0x33, 0xd2, 0xb0, 0xc6, 0x4e, 0x89, 0x8b, 0x56, 0x44,
        0xf6, 0x20, 0xa5, 0xbe, 0xd2, 0x5a, 0x06, 0x1a, 0x42, 0xfc, 0xdb,
    ]

    /// The HKDF info of the transaction viewing secret and of each transaction's key material.
    private static let info = Array("TSPP/tx_viewing".utf8)

    /// The length of the transaction viewing secret, in bytes.
    private static let secretLength = 32

    /// Derives the viewing key of one transaction.
    ///
    /// - Parameters:
    ///   - viewingKey: The sender account's viewing key.
    ///   - firstNullifier: The transaction's first nullifier.
    /// - Returns: The transaction viewing key.
    /// - Throws: ``P256Scalar/ValidationError/zeroScalar`` if the key material reduces to zero, or a
    ///   CryptoKit error if the key agreement fails.
    static func derive(viewingKey: P256.KeyAgreement.PrivateKey, firstNullifier: Poseidon.Element) throws -> P256.KeyAgreement.PrivateKey {
        let keyMaterial = try HKDF<SHA256>.deriveKey(
            inputKeyMaterial: secret(of: viewingKey), salt: firstNullifier.bigEndianBytes, info: info,
            outputByteCount: P256Scalar.keyMaterialLength
        )
        return try P256Scalar.privateKey(reducing: keyMaterial)
    }

    /// Derives an account's transaction viewing secret.
    ///
    /// - Parameter viewingKey: The account's viewing key.
    /// - Returns: The transaction viewing secret.
    /// - Throws: A CryptoKit error if the key agreement fails.
    private static func secret(of viewingKey: P256.KeyAgreement.PrivateKey) throws -> SymmetricKey {
        HKDF<SHA256>.expand(pseudoRandomKey: try viewRoot(of: viewingKey), info: info, outputByteCount: secretLength)
    }

    /// Derives an account's view root.
    ///
    /// - Parameter viewingKey: The account's viewing key.
    /// - Returns: The view root.
    /// - Throws: A CryptoKit error if the key agreement fails.
    private static func viewRoot(of viewingKey: P256.KeyAgreement.PrivateKey) throws -> HashedAuthenticationCode<SHA256> {
        let shared = try viewingKey.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(compressedRepresentation: viewRootPoint))
        return HKDF<SHA256>.extract(inputKeyMaterial: SymmetricKey(data: shared), salt: [UInt8]())
    }
}
