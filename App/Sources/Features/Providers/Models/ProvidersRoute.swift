/// A screen pushed inside Providers.
nonisolated enum ProvidersRoute: Hashable, Sendable {
    case customRPCSetup
    case customRPCDetails
    /// Helius's details.
    case providerDetails
    /// Entry of a new API key.
    case providerKey(ProviderEntryPurpose)
}
