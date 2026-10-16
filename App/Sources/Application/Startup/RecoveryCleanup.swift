import Vault

/// Deletes every recovery item and every private-balance key and note when no wallet is saved, so a reinstall or an
/// abandoned import leaves no secret behind.
///
/// Keychain items outlive the app's files. After a reinstall, or after an import that saved recovery but never
/// saved its account, a phrase can remain on the device with nothing referencing it. Saved wallets are never touched.
actor RecoveryCleanup: RecoveryCleaning {
    private let accounts: any AccountStoring
    private let recovery: any RecoveryStoring
    private let privateBalances: any PrivateBalancing
    private var run: Task<Void, any Error>?

    /// Connects the cleanup to the stores every window shares.
    /// - Parameters:
    ///   - accounts: The public wallet metadata that decides whether any recovery is still referenced.
    ///   - recovery: The protected storage whose unreferenced items are deleted.
    ///   - privateBalances: Each account's private-balance keys and notes, deleted with the recovery.
    init(accounts: any AccountStoring, recovery: any RecoveryStoring, privateBalances: any PrivateBalancing) {
        self.accounts = accounts
        self.recovery = recovery
        self.privateBalances = privateBalances
    }

    /// Runs the cleanup once per launch; concurrent windows wait for the same run, and a failed run can be retried.
    ///
    /// The run is an unstructured task so every window can await the same work. Nothing in it
    /// needs this actor, so it starts on the concurrent executor. The recovery and private-balance deletions run
    /// concurrently. Waiting on it is not cancellable; callers check cancellation after it returns.
    /// - Throws: A storage error from reading wallets or deleting recovery, keys, or notes.
    func complete() async throws {
        let run = self.run ?? Task { @concurrent [accounts, recovery, privateBalances] in
            guard try await accounts.load().isEmpty else { return }
            async let recoveryDeletion: Void = recovery.deleteAllRecovery()
            async let privateBalancesDeletion: Void = privateBalances.removeAll()
            _ = try await (recoveryDeletion, privateBalancesDeletion)
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
