import Foundation
import RPC
import Testing
import Vault
@testable import widgets

/// Records the order of reset deletions across every sensitive store, and whether the test's directory still existed
/// at each one, optionally failing one step once.
actor ResetStorage: RecoveryStoring {
    /// A store that a reset empties; the cases are in the order a reset empties them.
    nonisolated enum Step: String, Sendable, CaseIterable { case recovery, privateBalances, contacts, accounts, transactions, pendingTransactions, currency, key, settings, appearance }

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

    /// The shared contacts, accounts, transactions after one window read an account's records, currency choice, and
    /// provider settings, in the order the app erases them, each recording its erasure in this storage.
    @MainActor var stores: [any Erasable] {
        let transactions = TransactionStore(storage: { _ in ResetValue(storage: self, step: .transactions) },
                                            pending: ResetValue(storage: self, step: .pendingTransactions),
                                            coordinators: { _ in throw SubmitterError.noProviders })
        _ = transactions.records(for: TransactionRecord.Key(account: UUID(), network: .devnet))
        return [ContactStore(storage: ResetValue<AddressBook>(storage: self, step: .contacts)),
                AccountStore(storage: ResetValue<[widgets.Account]>(storage: self, step: .accounts),
                             cleanup: StartupRecoveryCleanup()),
                transactions,
                CurrencyStore(storage: ResetValue<CurrencySettings>(storage: self, step: .currency), rates: [:]),
                ProviderStore(settings: ResetValue<ProviderSettings>(storage: self, step: .settings),
                              key: ResetValue<String>(storage: self, step: .key))]
    }

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
    ///   - revision: Tells every window when the reset finishes.
    init(storage: ResetStorage, revision: Revision) {
        self.init(recovery: storage, privateBalances: storage.privateBalances, directories: [storage.directory],
                  appearance: storage.appearance, stores: storage.stores, revision: revision)
    }
}
