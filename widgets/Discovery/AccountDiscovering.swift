import Wallet

/// Coordinates local derivation and provider-neutral observations during phrase import.
nonisolated protocol AccountDiscovering: Sendable {
    /// Scans both approved hardened Solana path families over an explicit range.
    /// - Parameters:
    ///   - phrase: The imported and validated BIP-39 phrase.
    ///   - passphrase: The original BIP-39 passphrase, or an empty string for none.
    ///   - indices: One through ten indices below 2³¹; the initial range is `0..<10`.
    /// - Returns: SOL-funded accounts and the scanned network/range from one RPC request.
    /// - Throws: A range, derivation, RPC, response-validation, or cancellation error.
    ///   Failed scans never return partial results as a completed scan.
    func discover(for phrase: RecoveryPhrase, passphrase: String, indices: Range<UInt32>) async throws -> Discovery
}

extension AccountDiscovering {
    /// Checks twenty addresses at indices zero through nine in both approved families.
    /// - Parameters:
    ///   - phrase: The validated recovery phrase.
    ///   - passphrase: The original BIP-39 passphrase, or an empty string for none.
    /// - Returns: The completed initial scan.
    /// - Throws: A derivation, RPC, response-validation, or cancellation error.
    func discover(for phrase: RecoveryPhrase, passphrase: String = "") async throws -> Discovery {
        try await discover(for: phrase, passphrase: passphrase, indices: 0..<Discovery.indicesPerScan)
    }
}
