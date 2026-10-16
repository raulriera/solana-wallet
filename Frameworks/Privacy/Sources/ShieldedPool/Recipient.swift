import CryptoKit
import ModularArithmetic
import Transactions

/// A default-ring owner that can receive SOL: the public half of a shielded address.
///
/// The signing address is the owner's Ed25519 public key. It's also the owner's view tag, the
/// 32 bytes that a deposit or transact output publishes so the owner's wallet finds the output. The
/// owner hash, which every UTXO of the owner commits to, is
/// `Poseidon(hash_bytes_33(0x53 ‖ signing address), nullifier public key)`. The viewing public key
/// receives the notes of the owner's outputs.
struct Recipient: Sendable {
    /// Keys that can't own a default-ring UTXO.
    enum ValidationError: Error, Equatable {
        /// The signing address isn't an Ed25519 point, such as a program-derived address, so no
        /// key could spend the owner's UTXOs.
        case offCurveSigningAddress
    }

    /// The owner's Ed25519 signing address.
    let signingAddress: Address

    /// The public key of the owner's ``NullifierKey``.
    let nullifierPublicKey: Poseidon.Element

    /// The owner's P-256 viewing public key.
    let viewingPublicKey: P256.KeyAgreement.PublicKey

    /// The owner hash that the owner's UTXOs commit to.
    let owner: Poseidon.Element

    /// The view tag that the owner's outputs publish: the signing address's bytes.
    var viewTag: [UInt8] { signingAddress.bytes }

    /// Creates a recipient from a shielded address's keys and derives its owner hash.
    ///
    /// - Parameters:
    ///   - signingAddress: The owner's Ed25519 signing address.
    ///   - nullifierPublicKey: The public key of the owner's nullifier key.
    ///   - viewingPublicKey: The owner's viewing public key.
    /// - Throws: ``ValidationError/offCurveSigningAddress`` if the signing address isn't an Ed25519
    ///   point.
    init(signingAddress: Address, nullifierPublicKey: Poseidon.Element, viewingPublicKey: P256.KeyAgreement.PublicKey) throws {
        guard signingAddress.isOnCurve else { throw ValidationError.offCurveSigningAddress }
        self.signingAddress = signingAddress
        self.nullifierPublicKey = nullifierPublicKey
        self.viewingPublicKey = viewingPublicKey
        owner = OwnerIdentity.ownerHash(signingPublicKey: signingAddress.bytes, nullifierPublicKey: nullifierPublicKey)
    }
}
