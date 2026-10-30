import Foundation

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
}
