import Foundation
import Portfolio

/// Applies RPC provider choices and custom RPC changes to the shared portfolio and every window.
@MainActor
struct ProviderSelection: ProviderSelecting {
    private let store: any ValueStoring<ProviderSettings>
    private let providerKey: any ValueStoring<String>
    private let portfolio: any PortfolioProviding
    private let revision: Revision

    /// Connects the choice to the stores and windows it changes.
    /// - Parameters:
    ///   - settings: Device-only storage for the provider choice and custom RPCs.
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
        guard try await update({ $0.select(provider) }) else { return }
        // The previous provider's work has ended even when its logos can't be removed, so windows observe again.
        defer { revision.advance() }
        try await portfolio.providerDidChange()
    }

    /// Saves a checked custom RPC, chooses it for every window, and ends the previous provider's portfolio work.
    /// - Parameter url: The checked HTTPS RPC URL; adding a listed RPC only chooses it.
    /// - Throws: A storage or cancellation error when the RPC can't be saved, which changes nothing; or a file-system
    ///   error when saved logos can't be removed, after the RPC is saved and windows observe again.
    func add(_ url: URL) async throws {
        guard try await update({ $0.add(url) }) else { return }
        // The previous provider's work has ended even when its logos can't be removed, so windows observe again.
        defer { revision.advance() }
        try await portfolio.providerDidChange()
    }

    /// Deletes a custom RPC and tells every window; deleting the RPC in use switches every window to Solana.
    /// - Parameter url: The RPC URL to delete; an unlisted URL changes nothing.
    /// - Throws: A storage or cancellation error when the deletion can't be saved, which changes nothing; or a
    ///   file-system error when saved logos can't be removed, after the deletion is saved and windows observe again.
    func remove(_ url: URL) async throws {
        let (listed, selectionChanged) = try await update { settings in
            settings.customRPCs.contains(url) ? (true, settings.remove(url)) : (false, false)
        }
        guard listed else { return }
        // Every window's list changes, so windows read the settings again even when the provider stays.
        defer { revision.advance() }
        if selectionChanged { try await portfolio.providerDidChange() }
    }

    /// Changes the saved settings in one storage step, so changes from several windows don't overwrite each other.
    /// - Parameter change: Changes the settings, which start from the defaults before anything is saved.
    /// - Returns: The change's result.
    /// - Throws: A storage or cancellation error, which changes nothing.
    private func update<Result: Sendable>(
        _ change: @escaping @Sendable (inout ProviderSettings) -> Result
    ) async throws -> Result {
        try await store.update { saved in
            let current = saved ?? ProviderSettings()
            var settings = current
            let result = change(&settings)
            // Unchanged defaults stay unsaved.
            if settings != current { saved = settings }
            return result
        }
    }
}
