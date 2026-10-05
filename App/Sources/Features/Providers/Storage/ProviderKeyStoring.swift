/// Keeps the RPC provider's API key on this device, independently of wallet recovery.
nonisolated protocol ProviderKeyStoring: Sendable {
    /// Reads the saved key.
    /// - Returns: The key, or `nil` before one is saved.
    /// - Throws: A storage or cancellation error.
    func key() async throws -> String?

    /// Saves a key, replacing any key already stored.
    /// - Parameter key: A key the provider has already accepted.
    /// - Throws: A storage or cancellation error.
    func save(_ key: String) async throws
}
