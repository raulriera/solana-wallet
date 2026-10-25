import Vault

/// Deletes every recovery item and every private-balance key, note, and redeem code when no wallet is saved, so a
/// reinstall or an abandoned import leaves no secret behind.
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
    ///   - privateBalances: Each account's private-balance keys, notes, and redeem codes, deleted with the recovery.
    init(accounts: any AccountStoring, recovery: any RecoveryStoring, privateBalances: any PrivateBalancing) {
        self.accounts = accounts
        self.recovery = recovery
        self.privateBalances = privateBalances
    }

    /// Runs the cleanup once per launch.
    ///
    /// Concurrent callers share the run, a failed run can be retried, and waiting isn't cancellable.
    ///
    /// - Throws: A storage error from reading wallets or deleting recovery or private balances.
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
