public import CryptoKit
import ModularArithmetic
public import Transactions

/// An account's Solana Rings keys: the signing address that tags and pays for its transactions, the
/// nullifier key that spends its UTXOs, and the viewing key that opens its notes.
///
/// The signing address is the account's Ed25519 public key and its view tag. The keys come from
/// Wallet's `PrivateBalanceKeys`. Descriptions and reflection omit every value.
public struct ShieldedAccount: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The account's Ed25519 signing address, which is also its view tag and fee payer.
    public let signingAddress: Address

    /// The account's nullifier key.
    let nullifierKey: NullifierKey

    /// The account's viewing key, which opens its notes and derives its transaction viewing keys.
    let viewingKey: P256.KeyAgreement.PrivateKey

    /// A description that omits the values.
    public var description: String { "ShieldedAccount" }

    /// A debugging description that omits the values.
    public var debugDescription: String { description }

    /// A reflection view that omits the values.
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// The account's shielded address, the public half of its keys.
    ///
    /// - Throws: ``Recipient/ValidationError/offCurveSigningAddress`` if the signing address isn't an
    ///   Ed25519 point.
    var recipient: Recipient {
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
    ///   - nullifierSecret: The 31-byte nullifier secret, such as Wallet's
    ///     `PrivateBalanceKeys.nullifierSecret`.
    ///   - viewingKey: The P-256 viewing key, such as Wallet's `PrivateBalanceKeys.viewingKey`.
    /// - Throws: ``NullifierKey/ValidationError/invalidSecretLength`` for a nullifier secret of
    ///   another length.
    public init(signingAddress: Address, nullifierSecret: SymmetricKey, viewingKey: P256.KeyAgreement.PrivateKey) throws {
        self.signingAddress = signingAddress
        nullifierKey = try NullifierKey(secret: nullifierSecret)
        self.viewingKey = viewingKey
    }
}
