import CryptoKit
public import RPC

/// Whether an account's signing address has a user-registry record, and whether the record
/// publishes the account's keys.
public enum Registration: Sendable, Equatable {
    /// The signing address has no record.
    case unregistered
    /// The record publishes the account's nullifier public key and viewing public key.
    case registered
    /// The record publishes other keys, such as keys that another app derived, so the account's
    /// keys can't spend or open the notes that others send to it.
    case registeredWithOtherKeys
}

extension ShieldedAccount {
    /// Reads the account's user-registry record with one finalized `getMultipleAccounts` read,
    /// which any provider serves.
    ///
    /// - Parameter rpc: The client of the network whose registry to read.
    /// - Returns: ``Registration/unregistered`` without a record; ``Registration/registered`` if the
    ///   record's nullifier public key and compressed viewing public key are the account's; else
    ///   ``Registration/registeredWithOtherKeys``.
    /// - Throws: An RPC error, or a validation error if the provider returns another number of
    ///   accounts or the account at the record's address isn't a valid record of the account.
    @concurrent
    public func registration(using rpc: some RPC) async throws -> Registration {
        guard let record = try await UserRegistry.recipients(of: [signingAddress], using: rpc).first ?? nil else {
            return .unregistered
        }
        let isOwn = record.nullifierPublicKey == nullifierKey.publicKey
            && record.viewingPublicKey.compressedRepresentation == viewingKey.publicKey.compressedRepresentation
        return isOwn ? .registered : .registeredWithOtherKeys
    }
}
