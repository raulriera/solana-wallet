import CryptoKit
import Foundation
import ModularArithmetic

/// The per-transaction viewing key that seals the notes of a transfer's outputs.
///
/// A sender derives one key for each transaction from its account's viewing key and the
/// transaction's first nullifier, the published nullifier of input slot 0, and publishes the key's
/// public key with the transaction.
///
/// - The view root is `HKDF-Extract(salt: "TSPP/view_root/x25519/v1", clamped viewing secret)`.
/// - The transaction viewing secret is `HKDF-Expand(view root, "TSPP/tx_viewing/x25519/v1", 32)`.
/// - The key's secret is `HKDF(salt: first nullifier, transaction viewing secret,
///   "TSPP/tx_viewing/x25519/v1", 32)`, clamped.
///
/// The clamped secrets are zeroed before they're released. CryptoKit holds the viewing key, the
/// transaction viewing secret, the key material, and the derived key. The view root is an HMAC
/// value that isn't erased.
enum TransactionViewingKey {
    /// The HKDF salt of the view root.
    private static let viewRootSalt = Array("TSPP/view_root/x25519/v1".utf8)

    /// The HKDF info of the transaction viewing secret and of each transaction's key material.
    private static let info = Array("TSPP/tx_viewing/x25519/v1".utf8)

    /// The length of the transaction viewing secret, in bytes.
    private static let secretLength = 32

    /// Derives the viewing key of one transaction.
    ///
    /// - Parameters:
    ///   - viewingKey: The sender account's viewing key, such as Wallet's
    ///     `PrivateBalanceKeys.viewingKey`.
    ///   - firstNullifier: The transaction's first nullifier, which salts the derivation as its
    ///     32-byte big-endian encoding.
    /// - Returns: The transaction viewing key, whose raw representation is its clamped secret.
    /// - Throws: A CryptoKit error if the key can't be created, which doesn't happen.
    static func derive(
        viewingKey: Curve25519.KeyAgreement.PrivateKey,
        firstNullifier: Poseidon.Element
    ) throws -> Curve25519.KeyAgreement.PrivateKey {
        let keyMaterial = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: secret(of: viewingKey), salt: firstNullifier.bigEndianBytes, info: info,
            outputByteCount: secretLength
        )
        var secret = clamped(keyMaterial)
        defer { secret.erase() }
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secret)
    }

    /// Derives an account's transaction viewing secret.
    ///
    /// - Parameter viewingKey: The account's viewing key.
    /// - Returns: `HKDF-Expand(view root, "TSPP/tx_viewing/x25519/v1", 32)`.
    private static func secret(of viewingKey: Curve25519.KeyAgreement.PrivateKey) -> SymmetricKey {
        HKDF<SHA256>.expand(pseudoRandomKey: viewRoot(of: viewingKey), info: info, outputByteCount: secretLength)
    }

    /// Derives an account's view root.
    ///
    /// - Parameter viewingKey: The account's viewing key.
    /// - Returns: `HKDF-Extract(salt: "TSPP/view_root/x25519/v1", clamped viewing secret)`.
    private static func viewRoot(of viewingKey: Curve25519.KeyAgreement.PrivateKey) -> HashedAuthenticationCode<SHA256> {
        var secret = clamped(viewingKey.rawRepresentation)
        defer { secret.erase() }
        return HKDF<SHA256>.extract(inputKeyMaterial: SymmetricKey(data: secret), salt: viewRootSalt)
    }

    /// Clamps an X25519 secret.
    ///
    /// - Parameter secret: The 32-byte secret.
    /// - Returns: The secret with its three lowest bits and its highest bit cleared and its second
    ///   highest bit set.
    /// - Precondition: `secret` contains exactly 32 bytes.
    private static func clamped(_ secret: some ContiguousBytes) -> [UInt8] {
        var bytes = secret.withUnsafeBytes { [UInt8]($0) }
        precondition(bytes.count == secretLength, "An X25519 secret has exactly 32 bytes.")
        bytes[0] &= 0b1111_1000
        bytes[secretLength - 1] = bytes[secretLength - 1] & 0b0111_1111 | 0b0100_0000
        return bytes
    }
}
