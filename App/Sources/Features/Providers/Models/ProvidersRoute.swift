/// A screen pushed inside Providers; routes never carry an RPC URL, which can hold a key.
nonisolated enum ProvidersRoute: Hashable, Sendable {
    /// Adding a custom RPC.
    case customRPCSetup
    /// A custom RPC's details.
    case customRPCDetails
    /// Helius's details: the saved key, mostly hidden.
    case providerDetails
    /// Entry of a new key, saved in place of any saved key, worded for adding or changing it.
    case providerKey(ProviderEntryPurpose)
}
