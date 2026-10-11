/// A provider problem that only a new key or another provider can fix.
///
/// It never contains the key or the URL.
nonisolated enum ProviderClientError: Error, Equatable {
    /// Helius is selected or being chosen, and no Helius API key is saved on this device.
    case missingKey
    /// Helius rejected the saved key.
    case invalidKey
    /// The saved custom RPC URL can't be used.
    case unusableEndpoint
}
