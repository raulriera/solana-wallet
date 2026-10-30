/// The commands that provider controls run.
@MainActor protocol ProviderActions: AnyObject {
    /// Chooses the provider in use, asking for its key first when none is saved.
    ///
    /// - Parameter provider: The provider to use.
    func select(_ provider: ProviderSettings.Provider)

    /// Shows a provider's details.
    ///
    /// - Parameter provider: The provider whose details to show.
    func showDetails(for provider: ProviderSettings.Provider)

    /// Opens the screen that checks and saves a new key.
    func changeKey()

    /// Opens the screen that checks and adds a custom RPC.
    func addCustomRPC()
}
