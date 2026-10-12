import Foundation

/// Changes the RPC provider that every window uses, and the custom RPCs to choose from.
@MainActor
protocol ProviderSelecting: Sendable {
    /// Reads the saved provider choice and custom RPCs.
    /// - Returns: The saved settings, or the defaults before anything is saved.
    /// - Throws: A storage or cancellation error.
    func settings() async throws -> ProviderSettings

    /// Saves a new provider choice, ends the previous provider's portfolio work, and has every window observe again.
    ///
    /// Choosing the provider in use changes nothing. Helius needs a saved key first, even when it's in use.
    /// - Parameter provider: The provider to use.
    /// - Throws: ``ProviderClientError/missingKey`` for Helius without a saved key, or a storage or cancellation
    ///   error when the choice can't be saved, which change nothing; or a file-system error when saved logos can't
    ///   be removed, after the choice is saved and windows observe again.
    func select(_ provider: ProviderSettings.Provider) async throws

    /// Saves a checked custom RPC, chooses it for every window, and ends the previous provider's portfolio work.
    ///
    /// Adding a listed RPC only chooses it.
    /// - Parameter url: The checked HTTPS RPC URL.
    /// - Throws: A storage or cancellation error when the RPC can't be saved, which changes nothing; or a file-system
    ///   error when saved logos can't be removed, after the RPC is saved and windows observe again.
    func add(_ url: URL) async throws

    /// Deletes a custom RPC and tells every window; deleting the RPC in use switches every window to Solana.
    ///
    /// Deleting an RPC that isn't listed changes nothing.
    /// - Parameter url: The RPC URL to delete.
    /// - Throws: A storage or cancellation error when the deletion can't be saved, which changes nothing; or a
    ///   file-system error when saved logos can't be removed, after the deletion is saved and windows observe again.
    func remove(_ url: URL) async throws
}
