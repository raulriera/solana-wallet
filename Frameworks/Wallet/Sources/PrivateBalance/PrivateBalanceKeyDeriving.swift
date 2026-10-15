/// A type that derives an account's Solana Rings private-balance keys from its recovery phrase.
public protocol PrivateBalanceKeyDeriving: Sendable {
    /// Derives an account's private-balance keys after checking the recovered account against the
    /// intended address.
    ///
    /// The keys follow the Solana Rings seed-phrase scenario. Only Solana accounts at
    /// `m/44'/501'/i'/0'` have them; the account index i selects their paths. The returned keys
    /// are secret, and the caller owns their protection and lifetime.
    ///
    /// - Parameters:
    ///   - phrase: The validated recovery phrase.
    ///   - expectedAddress: The exact Base58 address of the intended account.
    ///   - passphrase: The original BIP-39 passphrase, including significant whitespace.
    ///   - path: The account's derivation path, `m/44'/501'/i'/0'`.
    /// - Returns: The account's nullifier secret and viewing key.
    /// - Throws: ``PrivateBalanceError/unsupportedPath`` for another path,
    ///   ``PrivateBalanceError/accountMismatch`` if the recovered account differs,
    ///   `CancellationError` if cancelled, or a cryptographic error.
    func privateBalanceKeys(
        using phrase: RecoveryPhrase,
        expectedAddress: String,
        passphrase: String,
        path: DerivationPath
    ) async throws -> PrivateBalanceKeys
}
