import Wallet

/// A service that finds the accounts of a recovery phrase that hold SOL.
nonisolated protocol AccountDiscovering: Sendable {
    /// Finds the accounts with SOL at indices zero through nine of both Solana path families.
    ///
    /// - Parameters:
    ///   - phrase: The recovery phrase.
    ///   - passphrase: The passphrase, or an empty string for none.
    /// - Returns: The accounts with SOL, in derivation order.
    /// - Throws: A derivation, RPC, validation, or cancellation error.
    func discover(for phrase: RecoveryPhrase, passphrase: String) async throws -> [DerivedAccount]
}
