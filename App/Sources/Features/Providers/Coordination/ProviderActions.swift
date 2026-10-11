/// The window-owned commands available to provider controls.
@MainActor protocol ProviderActions: AnyObject {
    /// Chooses the provider that every window uses, asking for its key first when none is saved.
    ///
    /// Taps while another choice waits are ignored.
    /// - Parameter provider: The provider to use.
    func select(_ provider: ProviderSettings.Provider)

    /// Shows a provider's details, such as Helius's key entry; the provider in use stays.
    /// - Parameter provider: The provider whose details to show.
    func showDetails(for provider: ProviderSettings.Provider)
}
