/// A provider error that only a new key or another provider can fix.
nonisolated enum ProviderClientError: Error, Equatable {
    case missingKey
    case invalidKey
    /// The saved custom RPC URL can't be used.
    case unusableEndpoint
    /// The selected custom RPC doesn't serve the requested network.
    case unsupportedNetwork
    /// The provider choices or the key can't be read.
    case settingsUnreadable
}
