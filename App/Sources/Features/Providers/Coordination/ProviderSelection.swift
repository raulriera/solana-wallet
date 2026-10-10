import Portfolio

/// Applies a new RPC provider choice to the shared portfolio and every window.
@MainActor
struct ProviderSelection: ProviderSelecting {
    private let settings: any ValueStoring<ProviderSettings>
    private let portfolio: any PortfolioProviding
    private let revision: Revision

    /// Connects the choice to the stores and windows it changes.
    /// - Parameters:
    ///   - settings: Device-only storage for the provider choice.
    ///   - portfolio: The shared portfolio, whose client reads the choice before every request.
    ///   - revision: Tells every window when a provider change applies.
    init(settings: any ValueStoring<ProviderSettings>, portfolio: any PortfolioProviding, revision: Revision) {
        self.settings = settings
        self.portfolio = portfolio
        self.revision = revision
    }

    /// Saves a new provider choice, ends the previous provider's portfolio work, and has every window observe again.
    /// - Parameter provider: The provider to use.
    /// - Throws: A storage or cancellation error when the choice can't be saved, which changes nothing, or a
    ///   file-system error when saved logos can't be removed, after the choice is saved and windows observe again.
    func select(_ provider: ProviderSettings.Provider) async throws {
        var current = try await settings.load() ?? ProviderSettings()
        guard current.select(provider) else { return }
        try await settings.save(current)
        // The previous provider's work has ended even when its logos can't be removed, so windows observe again.
        defer { revision.advance() }
        try await portfolio.providerDidChange()
    }
}
