import Foundation
import RPC

/// A type that unlocks a wallet and signs an approved preparation.
nonisolated protocol TransactionSigning: Sendable {
    /// Validates a reviewed message and signs it, authenticating the owner of a saved account.
    ///
    /// - Parameters:
    ///   - preparation: The preparation that the person reviewed.
    ///   - authority: The account that signs.
    ///   - reason: The localized reason for authentication.
    /// - Returns: The preparation with its signed transaction.
    /// - Throws: A validation, RPC, storage, or signing error, or `CancellationError` if cancelled.
    func sign(_ preparation: Preparation, for authority: Authority, reason: String) async throws -> SignedTransaction

    /// Runs an operation whose signatures share one authentication of a saved account's owner.
    ///
    /// - Parameters:
    ///   - reason: The localized reason for authentication, in place of the signatures' own reasons.
    ///   - operation: The work to run. It signs with the signer that it receives: the first signature authenticates
    ///     the owner, and later signatures reuse that authentication until the operation ends.
    /// - Returns: The operation's result.
    /// - Throws: The operation's error.
    func withSharedAuthentication<Value: Sendable>(
        reason: String, _ operation: @Sendable (any TransactionSigning) async throws -> Value
    ) async throws -> Value
}
