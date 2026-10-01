/// Persists public account metadata independently of protected recovery material.
nonisolated protocol AccountStoring: Sendable {
    /// Loads the accounts in their saved order.
    /// - Returns: Saved accounts, or an empty list before the first save.
    /// - Throws: A storage, validation, or cancellation error.
    func load() async throws -> [Account]

    /// Adds an account without replacing existing identities or derivation slots.
    /// - Parameter account: The account whose recovery has already been stored in Vault.
    /// - Returns: The complete list after the addition commits.
    /// - Throws: A duplicate, storage, validation, or pre-commit cancellation error.
    func add(_ account: Account) async throws -> [Account]
}
