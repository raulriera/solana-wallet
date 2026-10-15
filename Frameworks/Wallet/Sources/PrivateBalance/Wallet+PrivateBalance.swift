import CryptoKit

extension Wallet: PrivateBalanceKeyDeriving {
    /// Derives an account's Solana Rings private-balance keys on the concurrent executor.
    ///
    /// One temporary BIP-39 seed derives the account's Ed25519 key, which must match the expected
    /// address before the role keys are derived. The nullifier secret is the Ed25519 node key at
    /// `m/44'/1392955331'/i'/1'/0'` without its first byte; the viewing key is the P-256 node key at
    /// `m/44'/1392955331'/i'/2'/0'`. The service retains no recovery material or keys after the call;
    /// intermediate bytes are erased on a best-effort basis.
    ///
    /// - Parameters:
    ///   - phrase: The validated recovery phrase.
    ///   - expectedAddress: The exact Base58 address that must match the recovered key.
    ///   - passphrase: The original BIP-39 passphrase.
    ///   - path: The account path, `m/44'/501'/i'/0'`.
    /// - Returns: The account's nullifier secret and viewing key.
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
            var nullifierNodeKey = try KeyDerivation.privateKey(
                seed: seed, path: .nullifierSecret(account: account), curve: .ed25519
            )
            defer { nullifierNodeKey.erase() }
            var viewingScalar = try KeyDerivation.privateKey(
                seed: seed, path: .viewingKey(account: account), curve: .p256
            )
            defer { viewingScalar.erase() }
            return try PrivateBalanceKeys(
                nullifierSecret: SymmetricKey(data: nullifierNodeKey.dropFirst()),
                viewingKey: P256.KeyAgreement.PrivateKey(rawRepresentation: viewingScalar)
            )
        }
        try Task.checkCancellation()
        return keys
    }
}
