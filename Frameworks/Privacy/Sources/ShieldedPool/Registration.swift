import CryptoKit
public import RPC

/// The user-registry state of an account's signing address.
public enum Registration: Sendable, Equatable {
    case unregistered
    /// The record publishes the account's keys.
    case registered
    case registeredWithOtherKeys
}

extension ShieldedAccount {
    /// Reads the account's user-registry record.
    ///
    /// - Parameter rpc: The client of the network whose registry to read.
    /// - Returns: The state of the account's record.
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
