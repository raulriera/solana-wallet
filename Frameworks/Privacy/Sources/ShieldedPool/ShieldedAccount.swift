public import CryptoKit
import ModularArithmetic
public import Transactions

/// An account's signing address and the keys that spend its UTXOs and open its notes.
public struct ShieldedAccount: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let signingAddress: Address

    let nullifierKey: NullifierKey

    let viewingKey: Curve25519.KeyAgreement.PrivateKey

    public var description: String { "ShieldedAccount" }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// The account's view tags: its signing address, then the x-coordinate of its viewing public key.
    var viewTags: [[UInt8]] {
        [signingAddress.bytes, Array(viewingKey.publicKey.rawRepresentation)]
    }

    /// The account's shielded address.
    public var recipient: Recipient {
        get throws {
            try Recipient(
                signingAddress: signingAddress, nullifierPublicKey: nullifierKey.publicKey, viewingPublicKey: viewingKey.publicKey
            )
        }
    }

    /// Creates an account from its signing address and private-balance keys.
    ///
    /// - Parameters:
    ///   - signingAddress: The account's Ed25519 signing address.
    ///   - nullifierSecret: The 31-byte nullifier secret.
    ///   - viewingKey: The P-256 viewing key.
    /// - Throws: ``NullifierKey/ValidationError/invalidSecretLength`` for a nullifier secret of
    ///   another length.
    public init(signingAddress: Address, nullifierSecret: SymmetricKey, viewingKey: Curve25519.KeyAgreement.PrivateKey) throws {
        self.signingAddress = signingAddress
        nullifierKey = try NullifierKey(secret: nullifierSecret)
        self.viewingKey = viewingKey
    }
}
