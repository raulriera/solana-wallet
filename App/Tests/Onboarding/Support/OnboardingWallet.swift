import Wallet

/// Real local derivation with an optional failure or cancellable suspension.
struct OnboardingWallet: WalletProviding {
    let gate: Suspension?
    let failure: (any Error)?

    /// Configures an isolated dependency without retaining any generated recovery.
    /// - Parameters:
    ///   - gate: Suspension before returning the derived public address, even after cancellation.
    ///   - failure: A scripted derivation error.
    init(gate: Suspension? = nil, failure: (any Error)? = nil) {
        self.gate = gate
        self.failure = failure
    }

    /// Generates real recovery material using the requested entropy size.
    /// - Parameter wordCount: The requested phrase length.
    /// - Returns: A locally generated phrase.
    /// - Throws: A generation error.
    func recoveryPhrase(wordCount: RecoveryPhrase.WordCount) throws -> RecoveryPhrase {
        try Wallet().recoveryPhrase(wordCount: wordCount)
    }

    /// Derives a real address, then can return it after cancellation to test the caller's own check.
    /// - Parameters:
    ///   - phrase: The recovery supplied by onboarding.
    ///   - passphrase: The original BIP-39 passphrase.
    ///   - path: The coordinator's chosen derivation path.
    /// - Returns: The derived public address.
    /// - Throws: The scripted error, cancellation, or a derivation error.
    func address(for phrase: RecoveryPhrase, passphrase: String, path: DerivationPath) async throws -> String {
        if let failure { throw failure }
        let address = try await Wallet().address(for: phrase, passphrase: passphrase, path: path)
        if let gate { await gate.suspend() }
        return address
    }

    /// Delegates batch derivation to the real wallet service.
    /// - Parameters:
    ///   - phrase: The public fixture phrase.
    ///   - passphrase: Its BIP-39 passphrase.
    ///   - paths: Requested account paths.
    /// - Returns: The derived public accounts.
    /// - Throws: A derivation or cancellation error.
    func accounts(for phrase: RecoveryPhrase, passphrase: String, paths: [DerivationPath]) async throws -> [DerivedAccount] {
        try await Wallet().accounts(for: phrase, passphrase: passphrase, paths: paths)
    }
}
