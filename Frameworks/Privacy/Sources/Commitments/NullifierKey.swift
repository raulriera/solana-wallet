import CryptoKit
import ModularArithmetic
import Redaction

/// The key that derives an account's nullifiers.
struct NullifierKey: Sendable, Redacted {
    /// An error that rejects a nullifier secret.
    enum ValidationError: Error, Equatable {
        case invalidSecretLength
    }

    /// The length of a nullifier secret, in bytes.
    private static let secretLength = 31

    private let secret: SymmetricKey

    /// The published half of the key, `Poseidon(secret)`.
    let publicKey: Poseidon.Element

    /// Creates a key from an account's nullifier secret.
    ///
    /// - Parameter secret: The 31-byte nullifier secret.
    /// - Throws: ``ValidationError/invalidSecretLength`` for a secret of another length.
    init(secret: SymmetricKey) throws {
        guard secret.bitCount == Self.secretLength * 8 else { throw ValidationError.invalidSecretLength }
        self.secret = secret
        publicKey = Poseidon.hash(PackedBytes.field(of: secret))
    }

    var secretElement: Poseidon.Element {
        PackedBytes.field(of: secret)
    }

    /// Derives the nullifier that spending a UTXO publishes.
    ///
    /// - Parameters:
    ///   - utxoHash: The UTXO's hash.
    ///   - blinding: The UTXO's blinding.
    /// - Returns: `Poseidon(utxoHash, blinding, secret)`.
    func nullifier(utxoHash: Poseidon.Element, blinding: Poseidon.Element) -> Poseidon.Element {
        Poseidon.hash(utxoHash, blinding, secretElement)
    }
}
