/// Verifies and saves the API key for the app's RPC provider.
nonisolated protocol ProviderConnecting: Sendable {
    /// Checks a key with the provider, then saves it on this device.
    /// - Parameter apiKey: The key as entered; surrounding whitespace is ignored.
    /// - Throws: ``ProviderConnectionError`` or `CancellationError`, never containing the key.
    func connect(apiKey: String) async throws
}
