public import CryptoKit

/// An account's Solana Rings private-balance secrets.
public struct PrivateBalanceKeys: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The 31-byte secret that derives the account's nullifiers.
    public let nullifierSecret: SymmetricKey

    public let viewingKey: Curve25519.KeyAgreement.PrivateKey

    /// The 32-byte root that derives the account's one-time accounts.
    public let codeRoot: SymmetricKey

    public var description: String { "PrivateBalanceKeys" }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Creates an account's keys from a SLIP-0010 seed.
    ///
    /// - Parameters:
    ///   - seed: A BIP-39 seed or a one-time account's secret.
    ///   - account: The account index i, below 2³¹.
    /// - Throws: `CancellationError` if cancelled, or a cryptographic error.
    init(seed: [UInt8], account: UInt32) throws {
        var nullifierNodeKey = try KeyDerivation.privateKey(
            seed: seed, path: .nullifierSecret(account: account), curve: .ed25519
        )
        defer { nullifierNodeKey.erase() }
        var viewingNodeKey = try KeyDerivation.privateKey(
            seed: seed, path: .viewingKey(account: account), curve: .ed25519
        )
        defer { viewingNodeKey.erase() }
        var codeRootKey = try KeyDerivation.privateKey(seed: seed, path: .codeRoot(account: account), curve: .ed25519)
        defer { codeRootKey.erase() }
        nullifierSecret = SymmetricKey(data: nullifierNodeKey.dropFirst())
        viewingKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: viewingNodeKey)
        codeRoot = SymmetricKey(data: codeRootKey)
    }
}
