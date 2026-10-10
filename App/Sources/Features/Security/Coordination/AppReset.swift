import Vault

/// Deletes recovery phrases first, so a failed later step never leaves secrets behind.
@MainActor
struct AppReset: AppResetting {
    private let recovery: any RecoveryStoring
    private let accounts: any AccountStoring
    private let providerKeys: any ProviderKeyStoring
    private let revision: Revision

    /// Connects the reset to every store that holds sensitive data.
    /// - Parameters:
    ///   - recovery: The protected recovery storage.
    ///   - accounts: The public wallet metadata.
    ///   - providerKeys: The provider's API key storage.
    ///   - revision: Tells every window when the reset finishes.
    init(recovery: any RecoveryStoring, accounts: any AccountStoring, providerKeys: any ProviderKeyStoring,
         revision: Revision) {
        self.recovery = recovery
        self.accounts = accounts
        self.providerKeys = providerKeys
        self.revision = revision
    }

    /// Deletes every recovery phrase, then every wallet, then the provider API key, and returns every window to onboarding.
    /// - Throws: A storage or cancellation error from the first step that fails.
    func reset() async throws {
        try await recovery.deleteAllRecovery()
        try await accounts.removeAll()
        try await providerKeys.deleteKey()
        revision.advance()
    }
}
