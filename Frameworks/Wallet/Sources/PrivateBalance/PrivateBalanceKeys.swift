public import CryptoKit

/// An account's Solana Rings private-balance secrets.
///
/// Access ``nullifierSecret``, ``viewingKey``, and ``codeRoot`` explicitly; descriptions and
/// reflection omit them. CryptoKit holds the secrets; Swift doesn't guarantee that copies are
/// erased from memory.
public struct PrivateBalanceKeys: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The 31-byte secret that derives the account's nullifiers.
    public let nullifierSecret: SymmetricKey

    /// The P-256 viewing key, used for HPKE decryption and to derive view-tag secrets.
    public let viewingKey: P256.KeyAgreement.PrivateKey

    /// The 32-byte root that derives the account's one-time accounts with
    /// ``OneTimeAccount/init(codeRoot:index:)``.
    public let codeRoot: SymmetricKey

    /// A description that omits the secrets.
    public var description: String { "PrivateBalanceKeys" }

    /// A debugging description that omits the secrets.
    public var debugDescription: String { description }

    /// A reflection view that omits the secrets.
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Derives the keys of one account from a SLIP-0010 seed.
    ///
    /// The nullifier secret is the Ed25519 node key at `m/44'/1392955331'/i'/1'/0'` without its
    /// first byte, the viewing key is the P-256 node key at `m/44'/1392955331'/i'/2'/0'`, and the
    /// code root is the Ed25519 node key at `m/44'/1392955331'/i'/3'`. Intermediate bytes are erased
    /// on a best-effort basis.
    ///
    /// - Parameters:
    ///   - seed: The seed bytes: a BIP-39 seed, or a one-time account's secret.
    ///   - account: The account index i, below 2³¹.
    /// - Throws: `CancellationError` if cancelled, or a cryptographic error.
    init(seed: [UInt8], account: UInt32) throws {
        var nullifierNodeKey = try KeyDerivation.privateKey(
            seed: seed, path: .nullifierSecret(account: account), curve: .ed25519
        )
        defer { nullifierNodeKey.erase() }
        var viewingScalar = try KeyDerivation.privateKey(seed: seed, path: .viewingKey(account: account), curve: .p256)
        defer { viewingScalar.erase() }
        var codeRootKey = try KeyDerivation.privateKey(seed: seed, path: .codeRoot(account: account), curve: .ed25519)
        defer { codeRootKey.erase() }
        nullifierSecret = SymmetricKey(data: nullifierNodeKey.dropFirst())
        viewingKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: viewingScalar)
        codeRoot = SymmetricKey(data: codeRootKey)
    }
}
