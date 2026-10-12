/// The window-owned commands available to provider controls.
@MainActor protocol ProviderActions: AnyObject {
    /// Chooses the provider that every window uses, asking for its key first when none is saved.
    ///
    /// Taps while another change waits are ignored.
    /// - Parameter provider: The provider to use.
    func select(_ provider: ProviderSettings.Provider)

    /// Shows a provider's details, such as Helius's saved key; the provider in use stays.
    /// - Parameter provider: The provider whose details to show.
    func showDetails(for provider: ProviderSettings.Provider)

    /// Opens the screen that checks a new key and saves it in place of any saved key; the provider in use stays.
    func changeKey()

    /// Opens the screen that checks and adds a custom RPC.
    func addCustomRPC()
}
