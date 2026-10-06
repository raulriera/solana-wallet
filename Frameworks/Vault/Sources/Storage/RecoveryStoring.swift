public import Foundation

/// A type that stores wallet recovery material separately from wallet derivation.
public protocol RecoveryStoring: Sendable {
    /// Saves recovery material without replacing an existing wallet.
    ///
    /// - Parameters:
    ///   - recovery: The shared phrase and original BIP-39 passphrase to protect.
    ///   - walletID: The local identifier assigned by the caller.
    /// - Throws: An error if protection is unavailable or the wallet already exists.
    func save(_ recovery: Recovery, for walletID: UUID) async throws

    /// Retrieves recovery material after authenticating the user.
    ///
    /// - Parameters:
    ///   - walletID: The local wallet identifier.
    ///   - reason: A localized explanation of why the user must authenticate; never include secrets.
    /// - Returns: The stored recovery material.
    /// - Throws: `CancellationError` for cancellation, or an error if the item can't be accessed.
    func recovery(for walletID: UUID, reason: String) async throws -> Recovery

    /// Deletes the recovery material for one wallet.
    ///
    /// - Parameter walletID: The local wallet identifier to remove.
    /// - Throws: An error if deletion fails. An absent item is already deleted.
    func deleteRecovery(for walletID: UUID) async throws

    /// Deletes the recovery material for every wallet in this store.
    ///
    /// - Throws: An error if deletion fails. An empty store is already deleted.
    func deleteAllRecovery() async throws
}
