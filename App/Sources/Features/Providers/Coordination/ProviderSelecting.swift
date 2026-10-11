/// Changes the RPC provider that every window uses.
@MainActor
protocol ProviderSelecting {
    /// Saves a new provider choice, ends the previous provider's portfolio work, and has every window observe again.
    ///
    /// Choosing the provider in use changes nothing. Helius needs a saved key first, even when it's in use.
    /// - Parameter provider: The provider to use.
    /// - Throws: ``ProviderClientError/missingKey`` for Helius without a saved key, or a storage or cancellation
    ///   error when the choice can't be saved, which change nothing; or a file-system error when saved logos can't
    ///   be removed, after the choice is saved and windows observe again.
    func select(_ provider: ProviderSettings.Provider) async throws
}
