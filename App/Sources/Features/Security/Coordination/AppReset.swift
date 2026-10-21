import Vault

/// Deletes recovery phrases first, so a failed later step never leaves secrets behind.
@MainActor
struct AppReset: AppResetting {
    private let recovery: any RecoveryStoring
    private let privateBalances: any PrivateBalancing
    private let accounts: any AccountStoring
    private let providerKey: any ValueStoring<String>
    private let providerSettings: any ValueStoring<ProviderSettings>
    private let revision: Revision

    /// Connects the reset to every store that holds sensitive data.
    /// - Parameters:
    ///   - recovery: The protected recovery storage.
    ///   - privateBalances: Each account's private-balance keys, notes, and redeem codes.
    ///   - accounts: The public wallet metadata.
    ///   - providerKey: The provider's API key storage.
    ///   - providerSettings: The provider choice and custom RPC storage.
    ///   - revision: Tells every window when the reset finishes.
    init(recovery: any RecoveryStoring, privateBalances: any PrivateBalancing, accounts: any AccountStoring,
         providerKey: any ValueStoring<String>, providerSettings: any ValueStoring<ProviderSettings>, revision: Revision) {
        self.recovery = recovery
        self.privateBalances = privateBalances
        self.accounts = accounts
        self.providerKey = providerKey
        self.providerSettings = providerSettings
        self.revision = revision
    }

    /// Deletes every recovery phrase, then the private-balance keys, notes, and redeem codes, then every wallet, then the
    /// provider API key, then the provider choice and custom RPCs, and returns every window to onboarding.
    /// - Throws: A storage or cancellation error from the first step that fails.
    func reset() async throws {
        try await recovery.deleteAllRecovery()
        try await privateBalances.removeAll()
        try await accounts.removeAll()
        try await providerKey.delete()
        try await providerSettings.delete()
        revision.advance()
    }
}
