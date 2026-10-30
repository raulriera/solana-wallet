import Wallet

struct OnboardingWallet: WalletProviding {
    let gate: Suspension?
    let error: (any Error)?

    init(gate: Suspension? = nil, error: (any Error)? = nil) {
        self.gate = gate
        self.error = error
    }

    func recoveryPhrase(wordCount: RecoveryPhrase.WordCount) throws -> RecoveryPhrase {
        try Wallet().recoveryPhrase(wordCount: wordCount)
    }

    func accounts(for phrase: RecoveryPhrase, passphrase: String, paths: [DerivationPath]) async throws -> [DerivedAccount] {
        if let error { throw error }
        let accounts = try await Wallet().accounts(for: phrase, passphrase: passphrase, paths: paths)
        if let gate { await gate.suspend() }
        return accounts
    }
}
