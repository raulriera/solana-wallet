/// A cleanup that deletes recovery and private-balance secrets when no wallet is saved.
nonisolated protocol RecoveryCleaning: Sendable {
    /// Runs the cleanup once and waits for it to finish.
    ///
    /// - Throws: A storage error if the saved wallets can't be read or the secrets can't be deleted.
    func complete() async throws
}
