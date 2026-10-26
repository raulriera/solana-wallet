import Foundation
import RPC
import Testing
import Vault
@testable import widgets

/// Records the order of reset deletions across every sensitive store, and whether the test's directory still existed
/// at each one, optionally failing one step once.
actor ResetStorage: RecoveryStoring {
    /// A store that a reset empties; the cases are in the order a reset empties them.
    nonisolated enum Step: String, Sendable, CaseIterable { case recovery, privateBalances, appearance, contacts, accounts, transactions, pendingTransactions, key, settings }

    /// The test's own directory, which stands in for the app's kept and cached files.
    nonisolated let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    private var failing: Step?
    private(set) var deletions: [Step] = []
    /// Whether ``directory`` existed at each recorded deletion, in the same order.
    private(set) var directoryExisted: [Bool] = []

    /// Configures one test's stores.
    /// - Parameter failingOnce: The step whose first deletion throws, if any.
    init(failingOnce: Step? = nil) {
        failing = failingOnce
    }

    /// Deletes every recovery item, unless this step fails.
    /// - Throws: A scripted failure.
    func deleteAllRecovery() async throws { try delete(.recovery) }

    /// Each account's private-balance keys and notes, whose deletion this storage records.
    nonisolated var privateBalances: ResetPrivateBalances { ResetPrivateBalances(storage: self) }

    /// The shared appearance, whose restart this storage records.
    @MainActor var appearance: ResetAppearance { ResetAppearance(storage: self) }

    /// The shared contacts, whose erasure this storage records.
    @MainActor var contacts: ContactStore { ContactStore(storage: ResetValue<AddressBook>(storage: self, step: .contacts)) }

    /// The shared accounts, whose erasure this storage records.
    @MainActor var accounts: AccountStore {
        AccountStore(storage: ResetValue<[widgets.Account]>(storage: self, step: .accounts), cleanup: StartupRecoveryCleanup())
    }

    /// The shared transactions after one window read an account's records, whose erasure this storage records.
    @MainActor var transactions: TransactionStore {
        let store = TransactionStore(storage: { _ in ResetValue(storage: self, step: .transactions) },
                                     pending: ResetValue(storage: self, step: .pendingTransactions)) { _ in
            throw SubmitterError.noProviders
        }
        _ = store.records(for: TransactionRecord.Key(account: UUID(), network: .devnet))
        return store
    }

    /// The provider's API key, whose deletion this storage records.
    nonisolated var key: ResetValue<String> { ResetValue(storage: self, step: .key) }

    /// The provider choice and custom RPCs, whose deletion this storage records.
    nonisolated var settings: ResetValue<ProviderSettings> { ResetValue(storage: self, step: .settings) }

    /// Records a successful deletion or throws the step's one scripted failure.
    /// - Parameter step: The store being emptied.
    /// - Throws: A write error the first time the failing step runs.
    func delete(_ step: Step) throws {
        if failing == step {
            failing = nil
            throw CocoaError(.fileWriteUnknown)
        }
        deletions.append(step)
        directoryExisted.append(FileManager.default.fileExists(atPath: directory.path))
    }

    /// Reports any write, because a reset only deletes.
    /// - Parameters:
    ///   - recovery: The recovery the caller tried to save.
    ///   - recoveryID: The identity the caller tried to save under.
    func save(_ recovery: Recovery, for recoveryID: UUID) async throws { Issue.record("A reset must not save recovery.") }

    /// Reports any read, because a reset never unlocks recovery.
    /// - Parameters:
    ///   - recoveryID: The identity the caller tried to read.
    ///   - reason: The caller's authentication explanation.
    /// - Returns: Nothing; the read always fails.
    /// - Throws: A missing-recovery error.
    func recovery(for recoveryID: UUID, reason: String) async throws -> Recovery {
        Issue.record("A reset must not read recovery.")
        throw KeychainStoreError.recoveryUnavailable
    }

    /// Reports a single-wallet deletion, because a reset deletes every wallet at once.
    /// - Parameter recoveryID: The identity the caller tried to delete.
    func deleteRecovery(for recoveryID: UUID) async throws { Issue.record("A reset must delete all recovery at once.") }
}

extension AppReset {
    /// Creates a reset whose every store records its deletion in one shared storage.
    /// - Parameters:
    ///   - storage: The storage that records every reset step.
    ///   - contacts: The shared contacts, or `nil` for contacts whose erasure the storage records.
    ///   - accounts: The shared accounts, or `nil` for accounts whose erasure the storage records.
    ///   - transactions: The shared transactions, or `nil` for transactions whose erasure the storage records.
    ///   - revision: Tells every window when the reset finishes.
    init(storage: ResetStorage, contacts: ContactStore? = nil, accounts: AccountStore? = nil,
         transactions: TransactionStore? = nil, revision: Revision) {
        self.init(recovery: storage, privateBalances: storage.privateBalances, directories: [storage.directory],
                  appearance: storage.appearance, contacts: contacts ?? storage.contacts,
                  accounts: accounts ?? storage.accounts, transactions: transactions ?? storage.transactions,
                  providerKey: storage.key, providerSettings: storage.settings, revision: revision)
    }
}
