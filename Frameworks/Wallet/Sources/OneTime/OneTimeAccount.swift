public import CryptoKit
import Encoding
public import Foundation
public import Redaction

/// A Solana account that a 32-byte secret alone recovers.
public struct OneTimeAccount: Sendable, Redacted {
    public let secret: SymmetricKey

    public let privateBalanceKeys: PrivateBalanceKeys

    private let signingKey: Curve25519.Signing.PrivateKey

    /// The Base58-encoded Ed25519 public key.
    public var address: String { Base58.encode(Array(signingKey.publicKey.rawRepresentation)) }

    /// Creates the one-time account at an index of a code root.
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

    /// Derives the address of the one-time account at an index of a code root.
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

    /// Derives the secret at an index of a code root.
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
        var secret = try KeyDerivation.privateKey(seed: seed, path: DerivationPath(indices: [index]))
        defer { secret.erase() }
        return SymmetricKey(data: secret)
    }

    /// Creates a one-time account from its secret.
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
    /// - Parameter message: The message bytes to sign.
    /// - Returns: A 64-byte Ed25519 signature.
    /// - Throws: ``SigningError/reservedMessage`` for a key derivation input, or a cryptographic error.
    public func signature(for message: Data) throws -> Data {
        guard !message.isDerivationInput else { throw SigningError.reservedMessage }
        return try signingKey.signature(for: message)
    }
}
