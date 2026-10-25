import Wallet

/// Finds a recovery phrase's SOL-funded accounts.
nonisolated protocol AccountDiscovering: Sendable {
    /// Checks twenty addresses: indices zero through nine in both approved hardened Solana path families.
    ///
    /// Zero-SOL accounts are intentionally excluded even if they own tokens or have history.
    /// - Parameters:
    ///   - phrase: The imported and validated BIP-39 phrase.
    ///   - passphrase: The original BIP-39 passphrase, or an empty string for none.
    /// - Returns: SOL-funded accounts in index order, with the change family preceding the account family;
    ///   empty when none has a positive SOL balance.
    /// - Throws: A derivation, RPC, response-validation, or cancellation error.
    ///   Failed scans never return partial results as a completed scan.
    func discover(for phrase: RecoveryPhrase, passphrase: String) async throws -> [DerivedAccount]
}
