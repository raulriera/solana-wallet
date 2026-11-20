public import Foundation

/// A type that stores wallet recovery material.
public protocol RecoveryStoring: Sendable {
    /// Saves recovery material without replacing an existing wallet.
    ///
    /// - Parameters:
    ///   - recovery: The recovery material to save.
    ///   - recoveryID: The recovery material's identifier.
    /// - Throws: An error if protection is unavailable or the wallet already exists.
    func save(_ recovery: Recovery, for recoveryID: UUID) async throws

    /// Retrieves recovery material after authenticating the user.
    ///
    /// - Parameters:
    ///   - recoveryID: The recovery material's identifier.
    ///   - reason: The localized reason to show during authentication.
    /// - Returns: The stored recovery material.
    /// - Throws: `CancellationError` if cancelled, or an error if the item can't be read.
    func recovery(for recoveryID: UUID, reason: String) async throws -> Recovery

    /// Runs an operation whose recovery reads share one authentication of the user.
    ///
    /// - Parameters:
    ///   - reason: The localized reason to show during authentication, in place of the reads' own reasons.
    ///   - operation: The work to run. It reads recovery from the store that it receives: the first read
    ///     authenticates the user, and later reads reuse that authentication until the operation ends.
    /// - Returns: The operation's result.
    /// - Throws: The operation's error.
    func withSharedAuthentication<Value: Sendable>(
        reason: String, _ operation: @Sendable (any RecoveryStoring) async throws -> Value
    ) async throws -> Value

    /// Deletes the recovery material for one wallet.
    ///
    /// - Parameter recoveryID: The identifier of the recovery material to delete.
    /// - Throws: An error if deletion fails.
    func deleteRecovery(for recoveryID: UUID) async throws

    /// Deletes the recovery material for every wallet in this store.
    ///
    /// - Throws: An error if deletion fails.
    func deleteAllRecovery() async throws
}

extension RecoveryStoring {
    /// Runs an operation with this store, where each recovery read authenticates the user on its own.
    ///
    /// - Parameters:
    ///   - reason: The localized reason, which this store doesn't show.
    ///   - operation: The work to run with this store.
    /// - Returns: The operation's result.
    /// - Throws: The operation's error.
    public func withSharedAuthentication<Value: Sendable>(
        reason: String, _ operation: @Sendable (any RecoveryStoring) async throws -> Value
    ) async throws -> Value {
        try await operation(self)
    }
}
