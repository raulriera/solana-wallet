import Vault

/// Deletes every recovery item when no wallet is saved, so a reinstall or an abandoned import leaves no phrase behind.
///
/// Keychain items outlive the app's files. After a reinstall, or after an import that saved recovery but never
/// saved its account, a phrase can remain on the device with nothing referencing it. Saved wallets are never touched.
actor RecoveryCleanup: RecoveryCleaning {
    private let accounts: any AccountStoring
    private let recovery: any RecoveryStoring
    private var run: Task<Void, any Error>?

    /// Connects the cleanup to the stores every window shares.
    /// - Parameters:
    ///   - accounts: The public wallet metadata that decides whether any recovery is still referenced.
    ///   - recovery: The protected storage whose unreferenced items are deleted.
    init(accounts: any AccountStoring, recovery: any RecoveryStoring) {
        self.accounts = accounts
        self.recovery = recovery
    }

    /// Runs the cleanup once per launch; concurrent windows wait for the same run, and a failed run can be retried.
    ///
    /// The run is an unstructured task so every window can await the same work. Nothing in it
    /// needs this actor, so it starts on the concurrent executor. Waiting on it is not cancellable;
    /// callers check cancellation after it returns.
    /// - Throws: A storage error from reading wallets or deleting recovery.
    func complete() async throws {
        let run = self.run ?? Task { @concurrent [accounts, recovery] in
            guard try await accounts.load().isEmpty else { return }
            try await recovery.deleteAllRecovery()
        }
        self.run = run
        do {
            try await run.value
        } catch {
            if self.run == run { self.run = nil }
            throw error
        }
    }
}
