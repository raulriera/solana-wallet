import Foundation
import Privacy
import Storage
import Testing
import Vault
@testable import widgets

/// Verifies the launch cleanup deletes only unreferenced recovery and private balances, once, and can be retried after a
/// failure.
@Suite(.timeLimit(.minutes(1)))
struct RecoveryCleanupTests {
    /// With no saved wallet, every recovery item and the private-balance keys and notes are deleted once even when
    /// several windows wait together.
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

    /// Saved wallets keep their recovery and private balances; the cleanup never deletes while any wallet exists.
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

    /// An unreadable wallet list never counts as empty, so recovery and private balances stay, and a later
    /// successful read runs the cleanup.
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

        // Only the test empties the unreadable list, as a person who removed the damaged file would.
        try await accounts.delete()
        try await cleanup.complete()
        #expect(await recovery.deletions == 1)
        #expect(await keys.value == nil)
        #expect(await notes.value == nil)
    }

    /// A failed deletion surfaces its error and is attempted again on the next completion.
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

    /// One account's notes entry, saved before a test starts.
    private static let notesEntry: PrivateBalances.Notes = ["devnet/fixture": NoteSyncState()]

    /// Creates private-balance key storage that already holds a value.
    /// - Returns: In-memory storage with an empty key list saved.
    private static func savedKeys() -> StoredValue<PrivateBalances.Keys> {
        StoredValue([:])
    }

    /// Creates private-note storage that already holds an entry.
    /// - Returns: In-memory storage with ``notesEntry`` saved.
    private static func savedNotes() -> StoredValue<PrivateBalances.Notes> {
        StoredValue(notesEntry)
    }

    /// Creates the production private balances over in-memory keys and notes, without any planned request.
    /// - Parameters:
    ///   - keys: The saved keys.
    ///   - notes: The saved notes.
    ///   - recovery: The startup recovery storage, which fails the test if read.
    /// - Returns: Private balances that the cleanup empties.
    @MainActor
    private static func privateBalances(keys: StoredValue<PrivateBalances.Keys>, notes: StoredValue<PrivateBalances.Notes>,
                                        recovery: StartupRecoveryStore) -> PrivateBalances {
        PrivateBalances.inMemory(keys: keys, notes: notes, recovery: recovery, responses: HTTPResponses([:]))
    }
}

