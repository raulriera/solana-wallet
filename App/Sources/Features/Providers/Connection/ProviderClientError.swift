/// A provider problem that only a new key or another provider can fix.
///
/// It never contains the key or the URL.
nonisolated enum ProviderClientError: Error, Equatable {
    /// The selected or chosen provider needs an API key, and none is saved on this device.
    case missingKey
    /// The selected provider rejected the saved key.
    case invalidKey
    /// The saved custom RPC URL can't be used.
    case unusableEndpoint
    /// The selected custom RPC doesn't serve the requested network; custom RPCs serve mainnet.
    case unsupportedNetwork
    /// The selected provider doesn't read private notes or prove private transfers.
    case privateNotesUnavailable
    /// The provider choice or its key can't be read on this device.
    case settingsUnreadable
}
