import Foundation

/// A type that unlocks a wallet and signs an approved V1 preparation.
nonisolated protocol TransactionSigning: Sendable {
    /// Signs the reviewed message after validating it and authenticating the wallet owner.
    ///
    /// Call this operation only after the user approves the preparation's details.
    /// Biometric authentication establishes wallet access; the caller owns transaction consent.
    ///
    /// - Parameters:
    ///   - preparation: The immutable preparation that the user reviewed.
    ///   - account: The selected account and its shared recovery identity.
    ///   - reason: A localized, secret-free explanation for biometric authentication.
    /// - Returns: The original preparation and its signed transaction.
    /// - Throws: A validation, RPC, storage, or signing error, or `CancellationError` if cancelled.
    func sign(_ preparation: Preparation, for account: Account, reason: String) async throws -> SignedTransaction
}
