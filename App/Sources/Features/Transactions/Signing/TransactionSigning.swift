import Foundation

/// A type that unlocks a wallet and signs an approved V1 preparation.
nonisolated protocol TransactionSigning: Sendable {
    /// Signs the reviewed message after validating it and, for a saved account, authenticating the wallet owner.
    ///
    /// Call this operation only after the user approves the preparation's details.
    /// Biometric or device passcode authentication establishes access to a saved account; a one-time
    /// account signs in memory without authentication. The caller owns transaction consent.
    ///
    /// - Parameters:
    ///   - preparation: The immutable preparation that the user reviewed.
    ///   - authority: The selected saved or one-time account whose slot this signature fills.
    ///   - reason: A localized, secret-free explanation for authentication; one-time accounts ignore it.
    /// - Returns: The original preparation and its signed transaction.
    /// - Throws: A validation, RPC, storage, or signing error, or `CancellationError` if cancelled.
    func sign(_ preparation: Preparation, for authority: Authority, reason: String) async throws -> SignedTransaction
}
