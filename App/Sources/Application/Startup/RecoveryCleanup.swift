import Storage
import Vault

/// Deletes every recovery item and private-balance secret when no wallet is saved.
actor RecoveryCleanup: RecoveryCleaning {
    private let accounts: any ValueStoring<[Account]>
    private let recovery: any RecoveryStoring
    private let privateBalances: any PrivateBalancing
    private var run: Task<Void, any Error>?

    /// Creates a cleanup.
    ///
    /// - Parameters:
    ///   - accounts: The saved accounts' storage.
    ///   - recovery: The recovery storage.
    ///   - privateBalances: The private-balance keys, notes, and redeem codes.
    init(accounts: any ValueStoring<[Account]>, recovery: any RecoveryStoring, privateBalances: any PrivateBalancing) {
        self.accounts = accounts
        self.recovery = recovery
        self.privateBalances = privateBalances
    }

    func complete() async throws {
        let run = self.run ?? Task { @concurrent [accounts, recovery, privateBalances] in
            guard try await accounts.load()?.isEmpty ?? true else { return }
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
