/// A key problem that only a new key can fix, never containing the key.
nonisolated enum HeliusClientError: Error, Equatable {
    /// No Helius API key is saved on this device.
    case missingKey
    /// Helius rejected the saved key.
    case invalidKey
}
