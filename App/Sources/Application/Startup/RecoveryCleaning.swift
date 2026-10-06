/// Removes recovery material that no saved wallet references, once per launch.
nonisolated protocol RecoveryCleaning: Sendable {
    /// Finishes the launch cleanup, running it on the first call and sharing that run with later callers.
    /// - Throws: A storage error if saved wallets can't be read or orphaned recovery can't be deleted.
    func complete() async throws
}
