extension Wallet: PrivateBalanceKeyDeriving {
    /// Derives an account's Solana Rings private-balance keys on the concurrent executor after checking the
    /// recovered account against `expectedAddress`. The service retains no recovery material.
    ///
    /// - Parameters:
    ///   - phrase: The validated recovery phrase.
    ///   - expectedAddress: The exact Base58 address that must match the recovered key.
    ///   - passphrase: The original BIP-39 passphrase.
    ///   - path: The account path, `m/44'/501'/i'/0'`.
    /// - Returns: The account's nullifier secret, viewing key, and code root.
    /// - Throws: ``PrivateBalanceError/unsupportedPath`` for another path,
    ///   ``PrivateBalanceError/accountMismatch`` for a different account,
    ///   `CancellationError` if cancelled, or a cryptographic error.
    @concurrent
    public func privateBalanceKeys(
        using phrase: RecoveryPhrase,
        expectedAddress: String,
        passphrase: String,
        path: DerivationPath
    ) async throws -> PrivateBalanceKeys {
        try Task.checkCancellation()
        guard let account = path.privateBalanceAccount else { throw PrivateBalanceError.unsupportedPath }
        let keys = try Self.withVerifiedAccount(
            phrase, passphrase: passphrase, path: path, expectedAddress: expectedAddress,
            mismatch: PrivateBalanceError.accountMismatch
        ) { _, seed in
            try PrivateBalanceKeys(seed: seed, account: account)
        }
        try Task.checkCancellation()
        return keys
    }
}
