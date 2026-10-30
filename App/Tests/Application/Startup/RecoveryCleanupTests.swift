import Foundation
import Privacy
import Storage
import Testing
import Vault
@testable import widgets

@Suite(.timeLimit(.minutes(1)))
struct RecoveryCleanupTests {
    @Test
    func `An empty installation deletes orphaned recovery and private balances once for every window`() async throws {
        let recovery = StartupRecoveryStore()
        let keys = Self.savedKeys()
        let notes = Self.savedNotes()
        let cleanup = RecoveryCleanup(accounts: StoredValue<[Account]>(), recovery: recovery,
                                      privateBalances: await Self.privateBalances(keys: keys, notes: notes,
                                                                                  recovery: recovery))

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<3 { group.addTask { try await cleanup.complete() } }
            try await group.waitForAll()
        }
        try await cleanup.complete()

        #expect(await recovery.deletions == 1)
        #expect(await keys.value == nil)
        #expect(await notes.value == nil)
    }

    @Test
    func `Saved wallets keep their recovery and private balances`() async throws {
        let recovery = StartupRecoveryStore()
        let keys = Self.savedKeys()
        let notes = Self.savedNotes()
        let saved = try [Account.fixture(index: 0)]
        let cleanup = RecoveryCleanup(accounts: StoredValue(saved), recovery: recovery,
                                      privateBalances: await Self.privateBalances(keys: keys, notes: notes,
                                                                                  recovery: recovery))

        try await cleanup.complete()

        #expect(await recovery.deletions == 0)
        #expect(await keys.value == [:])
        #expect(await notes.value == Self.notesEntry)
    }

    @Test
    func `An unreadable wallet list is not treated as empty until a retry reads it`() async throws {
        let recovery = StartupRecoveryStore()
        let keys = Self.savedKeys()
        let notes = Self.savedNotes()
        let accounts = StoredValue<[Account]>(unreadable: true)
        let cleanup = RecoveryCleanup(accounts: accounts, recovery: recovery,
                                      privateBalances: await Self.privateBalances(keys: keys, notes: notes,
                                                                                  recovery: recovery))

        await #expect(throws: KeychainItemError.unreadable) { try await cleanup.complete() }
        #expect(await recovery.deletions == 0)
        #expect(await keys.value == [:])
        #expect(await notes.value == Self.notesEntry)

        try await accounts.delete()
        try await cleanup.complete()
        #expect(await recovery.deletions == 1)
        #expect(await keys.value == nil)
        #expect(await notes.value == nil)
    }

    @Test
    func `A failed deletion is retried`() async throws {
        let recovery = StartupRecoveryStore(error: KeychainStoreError.keychain(status: -1))
        let cleanup = RecoveryCleanup(accounts: StoredValue<[Account]>(), recovery: recovery,
                                      privateBalances: await Self.privateBalances(keys: Self.savedKeys(),
                                                                                  notes: Self.savedNotes(),
                                                                                  recovery: recovery))

        await #expect(throws: KeychainStoreError.keychain(status: -1)) { try await cleanup.complete() }
        await #expect(throws: KeychainStoreError.keychain(status: -1)) { try await cleanup.complete() }

        #expect(await recovery.deletions == 2)
    }

    private static let notesEntry: PrivateBalances.Notes = ["devnet/fixture": NoteSyncState()]

    private static func savedKeys() -> StoredValue<PrivateBalances.Keys> {
        StoredValue([:])
    }

    private static func savedNotes() -> StoredValue<PrivateBalances.Notes> {
        StoredValue(notesEntry)
    }

    @MainActor
    private static func privateBalances(keys: StoredValue<PrivateBalances.Keys>, notes: StoredValue<PrivateBalances.Notes>,
                                        recovery: StartupRecoveryStore) -> PrivateBalances {
        PrivateBalances.inMemory(keys: keys, notes: notes, recovery: recovery, responses: HTTPResponses([:]))
    }
}

