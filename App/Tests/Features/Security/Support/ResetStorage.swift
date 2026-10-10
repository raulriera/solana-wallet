import Foundation
import Testing
import Vault
@testable import widgets

/// Records the order of reset deletions across every sensitive store, optionally failing one step once.
actor ResetStorage: RecoveryStoring, AccountStoring {
    /// A store that a reset empties.
    enum Step: String, Sendable { case recovery, wallets, key }

    private var failing: Step?
    private(set) var deletions: [Step] = []

    /// Configures one test's stores.
    /// - Parameter failingOnce: The step whose first deletion throws, if any.
    init(failingOnce: Step? = nil) {
        failing = failingOnce
    }

    /// Deletes every recovery item, unless this step fails.
    /// - Throws: A scripted failure.
    func deleteAllRecovery() async throws { try delete(.recovery) }

    /// Deletes every wallet, unless this step fails.
    /// - Throws: A scripted failure.
    func removeAll() async throws { try delete(.wallets) }

    /// The provider's API key, whose deletion this storage records.
    nonisolated var key: ResetValue<String> { ResetValue(storage: self, step: .key) }

    /// Records a successful deletion or throws the step's one scripted failure.
    /// - Parameter step: The store being emptied.
    /// - Throws: A write error the first time the failing step runs.
    func delete(_ step: Step) throws {
        if failing == step {
            failing = nil
            throw CocoaError(.fileWriteUnknown)
        }
        deletions.append(step)
    }

    /// Reports any write, because a reset only deletes.
    /// - Parameters:
    ///   - recovery: The recovery the caller tried to save.
    ///   - walletID: The identity the caller tried to save under.
    func save(_ recovery: Recovery, for walletID: UUID) async throws { Issue.record("A reset must not save recovery.") }

    /// Reports any read, because a reset never unlocks recovery.
    /// - Parameters:
    ///   - walletID: The identity the caller tried to read.
    ///   - reason: The caller's authentication explanation.
    /// - Returns: Nothing; the read always fails.
    /// - Throws: A missing-recovery error.
    func recovery(for walletID: UUID, reason: String) async throws -> Recovery {
        Issue.record("A reset must not read recovery.")
        throw KeychainStoreError.recoveryUnavailable
    }

    /// Reports a single-wallet deletion, because a reset deletes every wallet at once.
    /// - Parameter walletID: The identity the caller tried to delete.
    func deleteRecovery(for walletID: UUID) async throws { Issue.record("A reset must delete all recovery at once.") }

    /// Returns no accounts.
    /// - Returns: An empty list.
    func load() async throws -> [widgets.Account] { [] }

    /// Reports any addition, because a reset only deletes.
    /// - Parameter account: The account the caller tried to add.
    /// - Returns: An empty list.
    func add(_ account: widgets.Account) async throws -> [widgets.Account] {
        Issue.record("A reset must not add accounts.")
        return []
    }
}
