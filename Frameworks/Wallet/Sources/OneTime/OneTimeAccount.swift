public import CryptoKit
import Encoding
public import Foundation

/// A Solana account that a 32-byte secret alone recovers, such as the account behind a redeem code.
///
/// The secret is a SLIP-0010 seed: the signing key is its Ed25519 node key at `m/44'/501'/0'/0'`,
/// and its private-balance keys are those of account 0. An account's code root derives one secret
/// per index. Access ``secret`` and ``privateBalanceKeys`` explicitly; descriptions and reflection
/// omit everything. CryptoKit holds the keys; Swift doesn't guarantee that copies are erased from memory.
public struct OneTimeAccount: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The 32-byte secret that recovers the account.
    public let secret: SymmetricKey

    /// The account's Solana Rings private-balance keys.
    public let privateBalanceKeys: PrivateBalanceKeys

    /// The Ed25519 key that signs for the account.
    private let signingKey: Curve25519.Signing.PrivateKey

    /// The Base58-encoded Ed25519 public key.
    public var address: String { Base58.encode(Array(signingKey.publicKey.rawRepresentation)) }

    /// A description that omits the secrets and the address.
    public var description: String { "OneTimeAccount" }

    /// A debugging description that omits the secrets and the address.
    public var debugDescription: String { description }

    /// A reflection view that omits the secrets and the address.
    public var customMirror: Mirror { Mirror(self, children: [:]) }

    /// Derives the one-time account at an index of a code root.
    ///
    /// The secret is the SLIP-0010 Ed25519 node key at `m/index'`, with the code root's 32 bytes as
    /// the seed. Intermediate bytes are erased on a best-effort basis.
    ///
    /// - Parameters:
    ///   - codeRoot: An account's 32-byte ``PrivateBalanceKeys/codeRoot``.
    ///   - index: The one-time account's index, below 2³¹.
    /// - Throws: ``OneTimeAccountError/invalidCodeRoot`` if the code root isn't 32 bytes,
    ///   ``OneTimeAccountError/invalidIndex`` if the index is 2³¹ or more,
    ///   `CancellationError` if cancelled, or a cryptographic error.
    public init(codeRoot: SymmetricKey, index: UInt32) throws {
        try self.init(secret: Self.secret(codeRoot: codeRoot, index: index))
    }

    /// Derives only the address of the one-time account at an index of a code root, without its
    /// private-balance keys, such as to look up many indices by view tag.
    ///
    /// The address is the one that ``init(codeRoot:index:)`` derives. Intermediate bytes are erased
    /// on a best-effort basis.
    ///
    /// - Parameters:
    ///   - codeRoot: An account's 32-byte ``PrivateBalanceKeys/codeRoot``.
    ///   - index: The one-time account's index, below 2³¹.
    /// - Returns: The Base58-encoded Ed25519 public key.
    /// - Throws: ``OneTimeAccountError/invalidCodeRoot`` if the code root isn't 32 bytes,
    ///   ``OneTimeAccountError/invalidIndex`` if the index is 2³¹ or more,
    ///   `CancellationError` if cancelled, or a cryptographic error.
    public static func address(codeRoot: SymmetricKey, index: UInt32) throws -> String {
        var seed = try secret(codeRoot: codeRoot, index: index).withUnsafeBytes { Array($0) }
        defer { seed.erase() }
        let signingKey = try KeyDerivation.signingKey(seed: seed, path: .solana)
        return Base58.encode(Array(signingKey.publicKey.rawRepresentation))
    }

    /// Derives the secret at an index of a code root: its SLIP-0010 Ed25519 node key at `m/index'`.
    ///
    /// - Parameters:
    ///   - codeRoot: An account's 32-byte code root.
    ///   - index: The index, below 2³¹.
    /// - Returns: The 32-byte secret.
    /// - Throws: ``OneTimeAccountError/invalidCodeRoot``, ``OneTimeAccountError/invalidIndex``,
    ///   `CancellationError`, or a cryptographic error.
    private static func secret(codeRoot: SymmetricKey, index: UInt32) throws -> SymmetricKey {
        guard codeRoot.bitCount == 256 else { throw OneTimeAccountError.invalidCodeRoot }
        guard index < DerivationPath.hardenedBit else { throw OneTimeAccountError.invalidIndex }
        var seed = codeRoot.withUnsafeBytes { Array($0) }
        defer { seed.erase() }
        var secret = try KeyDerivation.privateKey(seed: seed, path: DerivationPath(indices: [index]), curve: .ed25519)
        defer { secret.erase() }
        return SymmetricKey(data: secret)
    }

    /// Recovers a one-time account from its secret.
    ///
    /// Intermediate bytes are erased on a best-effort basis.
    ///
    /// - Parameter secret: The account's 32-byte secret.
    /// - Throws: ``OneTimeAccountError/invalidSecret`` if the secret isn't 32 bytes,
    ///   `CancellationError` if cancelled, or a cryptographic error.
    public init(secret: SymmetricKey) throws {
        guard secret.bitCount == 256 else { throw OneTimeAccountError.invalidSecret }
        var seed = secret.withUnsafeBytes { Array($0) }
        defer { seed.erase() }
        self.secret = secret
        signingKey = try KeyDerivation.signingKey(seed: seed, path: .solana)
        privateBalanceKeys = try PrivateBalanceKeys(seed: seed, account: 0)
    }

    /// Signs a message with the account's Ed25519 key.
    ///
    /// The caller supplies the exact message bytes and owns transaction validation.
    /// This method refuses Solana Rings key derivation inputs.
    ///
    /// - Parameter message: The exact unsigned message bytes; no signature or envelope is added.
    /// - Returns: A 64-byte Ed25519 signature. Signatures may vary between calls.
    /// - Throws: ``SigningError/reservedMessage`` for a key derivation input, or a cryptographic error.
    public func signature(for message: Data) throws -> Data {
        guard !message.isDerivationInput else { throw SigningError.reservedMessage }
        return try signingKey.signature(for: message)
    }
}
