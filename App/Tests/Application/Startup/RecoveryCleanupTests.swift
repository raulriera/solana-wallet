import Foundation
import Testing
import Vault
@testable import widgets

/// Verifies the launch cleanup deletes only unreferenced recovery, once, and can be retried after a failure.
@Suite(.timeLimit(.minutes(1)))
struct RecoveryCleanupTests {
    /// With no saved wallet, every recovery item is deleted once even when several windows wait together.
    @Test
    func `An empty installation deletes orphaned recovery once for every window`() async throws {
        let recovery = StartupRecoveryStore()
        let cleanup = RecoveryCleanup(accounts: StartupAccountStore { [] }, recovery: recovery)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<3 { group.addTask { try await cleanup.complete() } }
            try await group.waitForAll()
        }
        try await cleanup.complete()

        #expect(await recovery.deletions == 1)
    }

    /// Saved wallets keep their recovery; the cleanup never deletes while any wallet exists.
    @Test
    func `Saved wallets keep their recovery`() async throws {
        let recovery = StartupRecoveryStore()
        let saved = try [Account.fixture(index: 0)]
        let cleanup = RecoveryCleanup(accounts: StartupAccountStore { saved }, recovery: recovery)

        try await cleanup.complete()

        #expect(await recovery.deletions == 0)
    }

    /// An unreadable wallet list never counts as empty, and a later successful read runs the cleanup.
    @Test
    func `An unreadable wallet list is not treated as empty until a retry reads it`() async throws {
        let recovery = StartupRecoveryStore()
        let reads = Counter()
        let cleanup = RecoveryCleanup(accounts: StartupAccountStore {
            guard await reads.next() > 1 else { throw CocoaError(.fileReadNoPermission) }
            return []
        }, recovery: recovery)

        await #expect(throws: CocoaError.self) { try await cleanup.complete() }
        #expect(await recovery.deletions == 0)

        try await cleanup.complete()
        #expect(await recovery.deletions == 1)
    }

    /// A failed deletion surfaces its error and is attempted again on the next completion.
    @Test
    func `A failed deletion is retried`() async throws {
        let recovery = StartupRecoveryStore(error: KeychainStoreError.keychain(status: -1))
        let cleanup = RecoveryCleanup(accounts: StartupAccountStore { [] }, recovery: recovery)

        await #expect(throws: KeychainStoreError.keychain(status: -1)) { try await cleanup.complete() }
        await #expect(throws: KeychainStoreError.keychain(status: -1)) { try await cleanup.complete() }

        #expect(await recovery.deletions == 2)
    }
}

/// Counts calls across concurrent tasks.
private actor Counter {
    private var value = 0

    /// Increments and returns the new count.
    /// - Returns: The number of calls so far, including this one.
    func next() -> Int {
        value += 1
        return value
    }
}
