import Foundation
import RPC
import Testing
import Vault
@testable import widgets

actor ResetStorage: RecoveryStoring {
    nonisolated enum Step: String, Sendable, CaseIterable { case recovery, privateBalances, contacts, transactions, pendingTransactions, currency, key, settings, appearance, accounts }

    nonisolated let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    private var failing: Step?
    private(set) var deletions: [Step] = []
    private(set) var directoryExisted: [Bool] = []

    init(failingOnce: Step? = nil) {
        failing = failingOnce
    }

    func deleteAllRecovery() async throws { try delete(.recovery) }

    nonisolated var privateBalances: ResetPrivateBalances { ResetPrivateBalances(storage: self) }

    @MainActor var appearance: ResetAppearance { ResetAppearance(storage: self) }

    @MainActor var stores: [any Erasable] {
        let transactions = TransactionStore(storage: { _ in ResetValue(storage: self, step: .transactions) },
                                            pending: ResetValue(storage: self, step: .pendingTransactions),
                                            coordinators: { _ in throw TransactionCoordinatorError.unsupportedNetwork })
        _ = transactions.records(for: TransactionRecord.Key(account: UUID(), network: .devnet))
        return [ContactStore(storage: ResetValue<AddressBook>(storage: self, step: .contacts)),
                transactions,
                CurrencyStore(storage: ResetValue<CurrencySettings>(storage: self, step: .currency), rates: [:]),
                ProviderStore(settings: ResetValue<ProviderSettings>(storage: self, step: .settings),
                              key: ResetValue<String>(storage: self, step: .key))]
    }

    @MainActor var accounts: AccountStore {
        AccountStore(storage: ResetValue<[widgets.Account]>(storage: self, step: .accounts),
                     cleanup: StartupRecoveryCleanup())
    }

    func delete(_ step: Step) throws {
        if failing == step {
            failing = nil
            throw CocoaError(.fileWriteUnknown)
        }
        deletions.append(step)
        directoryExisted.append(FileManager.default.fileExists(atPath: directory.path))
    }

    func save(_ recovery: Recovery, for recoveryID: UUID) async throws { Issue.record("A reset must not save recovery.") }

    func recovery(for recoveryID: UUID, reason: String) async throws -> Recovery {
        Issue.record("A reset must not read recovery.")
        throw KeychainStoreError.recoveryUnavailable
    }

    func deleteRecovery(for recoveryID: UUID) async throws { Issue.record("A reset must delete all recovery at once.") }
}

extension AppReset {
    init(storage: ResetStorage) {
        self.init(recovery: storage, privateBalances: storage.privateBalances, directories: [storage.directory],
                  appearance: storage.appearance, stores: storage.stores, accounts: storage.accounts)
    }
}
