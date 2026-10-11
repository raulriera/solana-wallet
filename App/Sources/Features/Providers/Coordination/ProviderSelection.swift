import Portfolio

/// Applies a new RPC provider choice to the shared portfolio and every window.
@MainActor
struct ProviderSelection: ProviderSelecting {
    private let store: any ValueStoring<ProviderSettings>
    private let providerKey: any ValueStoring<String>
    private let portfolio: any PortfolioProviding
    private let revision: Revision

    /// Connects the choice to the stores and windows it changes.
    /// - Parameters:
    ///   - settings: Device-only storage for the provider choice.
    ///   - providerKey: Device-only storage for Helius's accepted key.
    ///   - portfolio: The shared portfolio, whose client reads the choice before every request.
    ///   - revision: Tells every window when a provider change applies.
    init(settings: any ValueStoring<ProviderSettings>, providerKey: any ValueStoring<String>,
         portfolio: any PortfolioProviding, revision: Revision) {
        store = settings
        self.providerKey = providerKey
        self.portfolio = portfolio
        self.revision = revision
    }

    /// Reads the saved provider choice and custom RPCs.
    /// - Returns: The saved settings, or the defaults before anything is saved.
    /// - Throws: A storage or cancellation error.
    func settings() async throws -> ProviderSettings {
        try await store.load() ?? ProviderSettings()
    }

    /// Saves a new provider choice, ends the previous provider's portfolio work, and has every window observe again.
    /// - Parameter provider: The provider to use.
    /// - Throws: ``ProviderClientError/missingKey`` for Helius without a saved key, or a storage or cancellation
    ///   error when the choice can't be saved, which change nothing; or a file-system error when saved logos can't
    ///   be removed, after the choice is saved and windows observe again.
    func select(_ provider: ProviderSettings.Provider) async throws {
        // Helius can't load anything without its key, so every window would lose its holdings.
        if provider == .helius, try await providerKey.load() == nil {
            try Task.checkCancellation()
            throw ProviderClientError.missingKey
        }
        var current = try await settings()
        guard current.select(provider) else { return }
        try await store.save(current)
        // The previous provider's work has ended even when its logos can't be removed, so windows observe again.
        defer { revision.advance() }
        try await portfolio.providerDidChange()
    }
}
