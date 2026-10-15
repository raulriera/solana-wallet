public import CryptoKit

/// An account's Solana Rings private-balance secrets.
///
/// Access ``nullifierSecret`` and ``viewingKey`` explicitly; descriptions and reflection omit them.
/// CryptoKit holds both secrets; Swift doesn't guarantee that copies are erased from memory.
public struct PrivateBalanceKeys: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The 31-byte secret that derives the account's nullifiers.
    public let nullifierSecret: SymmetricKey

    /// The P-256 viewing key, used for HPKE decryption and to derive view-tag secrets.
    public let viewingKey: P256.KeyAgreement.PrivateKey

    /// A description that omits the secrets.
    public var description: String { "PrivateBalanceKeys" }

    /// A debugging description that omits the secrets.
    public var debugDescription: String { description }

    /// A reflection view that omits the secrets.
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Creates the keys of one account.
    ///
    /// - Parameters:
    ///   - nullifierSecret: The 31-byte nullifier secret.
    ///   - viewingKey: The P-256 viewing key.
    init(nullifierSecret: SymmetricKey, viewingKey: P256.KeyAgreement.PrivateKey) {
        self.nullifierSecret = nullifierSecret
        self.viewingKey = viewingKey
    }
}
