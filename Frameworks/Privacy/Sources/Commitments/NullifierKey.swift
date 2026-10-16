import CryptoKit
import ModularArithmetic

/// The key that derives an account's Solana Rings nullifiers.
///
/// The 31-byte secret enters each hash right-aligned in a 32-byte big-endian value, which is below
/// 2^248 and so below r. The public key, `Poseidon(secret)`, enters the account's owner hash. A
/// UTXO's nullifier is `Poseidon(UTXO hash, blinding, secret)`. CryptoKit holds the secret, and each
/// hash encodes it with ``PackedBytes/field(of:)``, which zeroes its buffer. The secret's field
/// element and the Poseidon inputs and state that hold it are never erased. Descriptions and
/// reflection omit the secret.
struct NullifierKey: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// A secret that can't be a nullifier secret.
    enum ValidationError: Error, Equatable {
        /// A nullifier secret has exactly 31 bytes.
        case invalidSecretLength
    }

    /// The number of bytes in a nullifier secret.
    private static let secretLength = 31

    /// The 31-byte nullifier secret.
    private let secret: SymmetricKey

    /// The published half of the key, `Poseidon(secret)`.
    let publicKey: Poseidon.Element

    /// A description that omits the secret.
    var description: String { "NullifierKey" }

    /// A debugging description that omits the secret.
    var debugDescription: String { description }

    /// A reflection view that omits the secret.
    var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Creates the key of an account's nullifier secret and derives its public key.
    ///
    /// - Parameter secret: The 31-byte nullifier secret, such as Wallet's
    ///   `PrivateBalanceKeys.nullifierSecret`.
    /// - Throws: ``ValidationError/invalidSecretLength`` for a secret of another length.
    init(secret: SymmetricKey) throws {
        guard secret.bitCount == Self.secretLength * 8 else { throw ValidationError.invalidSecretLength }
        self.secret = secret
        publicKey = Poseidon.hash(PackedBytes.field(of: secret))
    }

    /// Derives the nullifier that spending a UTXO publishes.
    ///
    /// - Parameters:
    ///   - utxoHash: The UTXO's hash, which commits to this key's public key through its owner.
    ///   - blinding: The UTXO's blinding.
    /// - Returns: `Poseidon(utxoHash, blinding, secret)`.
    func nullifier(utxoHash: Poseidon.Element, blinding: Poseidon.Element) -> Poseidon.Element {
        Poseidon.hash(utxoHash, blinding, PackedBytes.field(of: secret))
    }
}
