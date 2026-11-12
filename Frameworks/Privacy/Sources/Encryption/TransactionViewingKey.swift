import CryptoKit
import Foundation
import ModularArithmetic
import Redaction

/// The per-transaction viewing key that seals the notes of a transaction's outputs.
enum TransactionViewingKey {
    private static let viewRootSalt = Array("TSPP/view_root/x25519/v1".utf8)

    /// The HKDF info of the transaction viewing secret and of each transaction's key material.
    private static let info = Array("TSPP/tx_viewing/x25519/v1".utf8)

    /// The length of the transaction viewing secret, in bytes.
    private static let secretLength = 32

    /// Derives the viewing key of one transaction.
    ///
    /// - Parameters:
    ///   - viewingKey: The sender account's viewing key.
    ///   - firstNullifier: The transaction's first nullifier.
    /// - Returns: The transaction viewing key.
    /// - Throws: A CryptoKit error if the key can't be created.
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
    /// - Returns: The transaction viewing secret.
    private static func secret(of viewingKey: Curve25519.KeyAgreement.PrivateKey) -> SymmetricKey {
        HKDF<SHA256>.expand(pseudoRandomKey: viewRoot(of: viewingKey), info: info, outputByteCount: secretLength)
    }

    /// Derives an account's view root.
    ///
    /// - Parameter viewingKey: The account's viewing key.
    /// - Returns: The view root.
    private static func viewRoot(of viewingKey: Curve25519.KeyAgreement.PrivateKey) -> HashedAuthenticationCode<SHA256> {
        var secret = clamped(viewingKey.rawRepresentation)
        defer { secret.erase() }
        return HKDF<SHA256>.extract(inputKeyMaterial: SymmetricKey(data: secret), salt: viewRootSalt)
    }

    /// Clamps an X25519 secret.
    ///
    /// - Parameter secret: The 32-byte secret.
    /// - Returns: The clamped secret.
    /// - Precondition: `secret` contains exactly 32 bytes.
    private static func clamped(_ secret: some ContiguousBytes) -> [UInt8] {
        var bytes = secret.withUnsafeBytes { [UInt8]($0) }
        precondition(bytes.count == secretLength, "An X25519 secret has exactly 32 bytes.")
        bytes[0] &= 0b1111_1000
        bytes[secretLength - 1] = bytes[secretLength - 1] & 0b0111_1111 | 0b0100_0000
        return bytes
    }
}
