import Wallet

/// Real local derivation with an optional failure or cancellable suspension.
struct OnboardingWallet: WalletProviding {
    let gate: Suspension?
    let error: (any Error)?

    /// Configures an isolated dependency without retaining any generated recovery.
    /// - Parameters:
    ///   - gate: Suspension before returning the derived public accounts, even after cancellation.
    ///   - error: A scripted derivation error.
    init(gate: Suspension? = nil, error: (any Error)? = nil) {
        self.gate = gate
        self.error = error
    }

    /// Generates real recovery material using the requested entropy size.
    /// - Parameter wordCount: The requested phrase length.
    /// - Returns: A locally generated phrase.
    /// - Throws: A generation error.
    func recoveryPhrase(wordCount: RecoveryPhrase.WordCount) throws -> RecoveryPhrase {
        try Wallet().recoveryPhrase(wordCount: wordCount)
    }

    /// Derives real accounts, then can return them after cancellation to test the caller's own check.
    /// - Parameters:
    ///   - phrase: The recovery supplied by onboarding.
    ///   - passphrase: The original BIP-39 passphrase.
    ///   - paths: The coordinator's chosen derivation paths.
    /// - Returns: The derived public accounts.
    /// - Throws: The scripted error, cancellation, or a derivation error.
    func accounts(for phrase: RecoveryPhrase, passphrase: String, paths: [DerivationPath]) async throws -> [DerivedAccount] {
        if let error { throw error }
        let accounts = try await Wallet().accounts(for: phrase, passphrase: passphrase, paths: paths)
        if let gate { await gate.suspend() }
        return accounts
    }
}
