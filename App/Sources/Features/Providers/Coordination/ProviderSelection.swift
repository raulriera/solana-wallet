import Foundation
import Portfolio
import Storage

/// Applies RPC provider choices and custom RPC changes to each created portfolio and every window.
@MainActor
struct ProviderSelection: ProviderSelecting {
    private let store: any ValueStoring<ProviderSettings>
    private let providerKey: any ValueStoring<String>
    private let portfolios: @MainActor @Sendable () -> [any PortfolioProviding]
    private let revisions: ProviderRevisions

    /// Connects the choice to the stores and windows it changes.
    /// - Parameters:
    ///   - settings: Device-only storage for the provider choice and custom RPCs.
    ///   - providerKey: Device-only storage for Helius's accepted key.
    ///   - portfolios: Returns the portfolios created so far, whose clients read the choice before every request.
    ///   - revisions: Tell every window when the settings change, and when portfolios use another provider.
    init(settings: any ValueStoring<ProviderSettings>, providerKey: any ValueStoring<String>,
         portfolios: @escaping @MainActor @Sendable () -> [any PortfolioProviding], revisions: ProviderRevisions) {
        store = settings
        self.providerKey = providerKey
        self.portfolios = portfolios
        self.revisions = revisions
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
    ///   error, which change nothing.
    func select(_ provider: ProviderSettings.Provider) async throws {
        // Helius can't load anything without its key, so every window would lose its holdings.
        if provider == .helius { _ = try await ProviderClient.heliusKey(in: providerKey) }
        try await apply { $0.select(provider) }
    }

    /// Saves a checked custom RPC, chooses it for every window, and ends the previous provider's portfolio work.
    /// - Parameter url: The checked HTTPS RPC URL; adding a listed RPC only chooses it.
    /// - Throws: A storage or cancellation error, which changes nothing.
    func add(_ url: URL) async throws {
        try await apply { $0.add(url) }
    }

    /// Deletes a custom RPC and tells every window; deleting the RPC in use switches every window to Solana.
    /// - Parameter url: The RPC URL to delete; an unlisted URL changes nothing.
    /// - Throws: A storage or cancellation error, which changes nothing.
    func remove(_ url: URL) async throws {
        try await apply { $0.remove(url) }
    }

    /// Saves a change in one storage step, so changes from several windows don't overwrite each other, then ends the
    /// previous provider's portfolio work when the provider changed and has every window observe again.
    ///
    /// Unchanged settings aren't saved and tell no window. The change is already saved, so logos that can't be
    /// removed, as on a full disk, don't undo it; they stay until a later change.
    /// - Parameter change: Changes the settings, which start from the defaults before anything is saved.
    /// - Throws: A storage or cancellation error, which changes nothing.
    private func apply(_ change: @escaping @Sendable (inout ProviderSettings) -> Void) async throws {
        let (old, new) = try await store.update { saved in
            let old = saved ?? ProviderSettings()
            var new = old
            change(&new)
            // Unchanged defaults stay unsaved.
            if new != old { saved = new }
            return (old, new)
        }
        guard new != old else { return }
        if new.selection != old.selection {
            // Logos that one portfolio can't remove don't keep another from ending its work.
            for portfolio in portfolios() { try? await portfolio.providerDidChange() }
            revisions.connection.advance()
        }
        // Every window's list can change even when the provider stays.
        revisions.settings.advance()
    }
}
