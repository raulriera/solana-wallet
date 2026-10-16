import CryptoKit
import Foundation
import ModularArithmetic

/// The per-transaction viewing key that seals the notes of a transfer's outputs.
///
/// A sender derives one key for each transaction from its account's viewing key and the
/// transaction's first nullifier, the published nullifier of input slot 0, and publishes the key's
/// public key with the transaction. The derivation follows zolana's
/// `ViewingKey.transactionViewingKey`:
///
/// - The view root is `HKDF-Extract(salt: empty, ECDH(viewing key, P_const))`, where ECDH gives
///   the x-coordinate of the shared point.
/// - The transaction viewing secret is `HKDF-Expand(view root, "TSPP/tx_viewing", 32)`.
/// - The key's scalar is `HKDF(salt: first nullifier, transaction viewing secret,
///   "TSPP/tx_viewing", 48)`, reduced modulo n by ``P256Scalar/privateKey(reducing:)``.
///
/// CryptoKit holds the viewing key, the shared secret, the transaction viewing secret, the key
/// material, and the derived key. The view root is an HMAC value that isn't erased.
enum TransactionViewingKey {
    /// P_const, the SEC1 compressed point that each account's view root derives from.
    ///
    /// The point is RFC 9380's `P256_XMD:SHA-256_SSWU_RO_` hash of the empty message under the
    /// domain separation tag `TSPP/view_root/P_const/v1`, pinned as zolana pins it.
    private static let viewRootPoint: [UInt8] = [
        0x03, 0x0e, 0x4d, 0xf9, 0x46, 0xbc, 0xe1, 0x4b, 0x95, 0x29, 0x2f,
        0x13, 0xe1, 0x33, 0xd2, 0xb0, 0xc6, 0x4e, 0x89, 0x8b, 0x56, 0x44,
        0xf6, 0x20, 0xa5, 0xbe, 0xd2, 0x5a, 0x06, 0x1a, 0x42, 0xfc, 0xdb,
    ]

    /// The HKDF info of the transaction viewing secret and of each transaction's key material.
    private static let info = Array("TSPP/tx_viewing".utf8)

    /// The number of bytes in the transaction viewing secret.
    private static let secretLength = 32

    /// Derives the viewing key of one transaction.
    ///
    /// - Parameters:
    ///   - viewingKey: The sender account's viewing key, such as Wallet's
    ///     `PrivateBalanceKeys.viewingKey`.
    ///   - firstNullifier: The transaction's first nullifier, which salts the derivation as its
    ///     32-byte big-endian encoding.
    /// - Returns: The transaction viewing key.
    /// - Throws: ``P256Scalar/ValidationError/zeroScalar`` if the key material reduces to zero,
    ///   which is negligibly unlikely, or a CryptoKit error if the key agreement fails.
    static func derive(viewingKey: P256.KeyAgreement.PrivateKey, firstNullifier: Poseidon.Element) throws -> P256.KeyAgreement.PrivateKey {
        let keyMaterial = try HKDF<SHA256>.deriveKey(
            inputKeyMaterial: secret(of: viewingKey), salt: firstNullifier.bigEndianBytes, info: info,
            outputByteCount: P256Scalar.keyMaterialLength
        )
        return try P256Scalar.privateKey(reducing: keyMaterial)
    }

    /// Derives an account's transaction viewing secret, which every transaction's key expands.
    ///
    /// - Parameter viewingKey: The account's viewing key.
    /// - Returns: `HKDF-Expand(view root, "TSPP/tx_viewing", 32)`.
    /// - Throws: A CryptoKit error if the key agreement fails.
    private static func secret(of viewingKey: P256.KeyAgreement.PrivateKey) throws -> SymmetricKey {
        HKDF<SHA256>.expand(pseudoRandomKey: try viewRoot(of: viewingKey), info: info, outputByteCount: secretLength)
    }

    /// Derives an account's view root, the key that all of its viewing secrets expand.
    ///
    /// - Parameter viewingKey: The account's viewing key.
    /// - Returns: `HKDF-Extract(salt: empty, ECDH(viewingKey, P_const))`.
    /// - Throws: A CryptoKit error if the key agreement fails.
    private static func viewRoot(of viewingKey: P256.KeyAgreement.PrivateKey) throws -> HashedAuthenticationCode<SHA256> {
        let shared = try viewingKey.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(compressedRepresentation: viewRootPoint))
        return HKDF<SHA256>.extract(inputKeyMaterial: SymmetricKey(data: shared), salt: [UInt8]())
    }
}
