import Foundation
@testable import RPC
import Storage
import Testing
import Transactions
@testable import widgets

/// Verifies the pending index and resuming watches through the real transaction coordinator, with local responses and
/// sockets, and in-memory records and index.
///
/// Each transaction pays 1 SOL from the fixture account on devnet; its blockhash is valid through block height 550.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TransactionStoreResumptionTests {
    // MARK: Pending index

    /// Sending lists the key in the pending index, and resuming removes the keys whose records all settled, so the
    /// index lists only keys with pending records.
    @Test
    func `The index lists only keys with pending records`() async throws {
        let settledKey = TransactionRecord.Key(account: UUID(), network: .devnet)
        let settled = StoredValue([TransactionRecord.fixture(.privateDeposit(lamports: 1), signature: "settled",
                                                             account: settledKey.account, status: .succeeded,
                                                             settled: 10)])
        let gate = Suspension()
        let resuming = try LocalSending(statusGate: gate, otherRecords: [settledKey: settled],
                                         pending: StoredValue([settledKey]))

        let record = try await resuming.send()
        #expect(await resuming.pending.value == [settledKey, resuming.key])
        await resuming.store.resume()

        #expect(await resuming.pending.value == [resuming.key])
        gate.resume()
        _ = try await resuming.settle(record)
    }

    /// A record that settles removes its key from the pending index.
    @Test
    func `A settled record leaves the index`() async throws {
        let resuming = try LocalSending()
        let record = try await resuming.send()

        #expect(try await resuming.settle(record) == .succeeded)

        #expect(await resuming.pending.value == [])
    }

    // MARK: Resuming

    /// Resuming reads only the keys in the pending index and watches their pending records; a key outside the index
    /// isn't read.
    @Test
    func `Resuming reads only the keys in the pending index`() async throws {
        let fixture = try SigningFixture()
        let record = try TransactionRecord.fixture(LocalSending.payment(), signature: "pending",
                                                   account: fixture.account.id)
        let skippedKey = TransactionRecord.Key(account: UUID(), network: .devnet)
        let skipped = StoredValue([try TransactionRecord.fixture(LocalSending.payment(), signature: "skipped",
                                                                 account: skippedKey.account)])
        let resuming = try LocalSending(fixture: fixture, records: StoredValue([record]),
                                         otherRecords: [skippedKey: skipped], pending: StoredValue([record.key]))

        await resuming.store.resume()

        #expect(await resuming.store.settledStatus(of: record) == .succeeded)
        #expect(await skipped.loads == 0)
        #expect(resuming.store.phase(for: skippedKey) == .unloaded)
        await resuming.sockets.waitUntilClosed()
    }

    /// Resuming again, at once or while the watch runs, starts no other watch.
    @Test
    func `Resuming starts no duplicate watches`() async throws {
        let fixture = try SigningFixture()
        let record = try TransactionRecord.fixture(LocalSending.payment(), signature: "pending",
                                                   account: fixture.account.id)
        let gate = Suspension()
        let resuming = try LocalSending(statusGate: gate, fixture: fixture, records: StoredValue([record]),
                                         pending: StoredValue([record.key]))
        let store = resuming.store

        await withDiscardingTaskGroup { group in
            group.addTask { await store.resume() }
            group.addTask { await store.resume() }
        }
        await gate.waitUntilStarted()
        await store.resume()

        gate.resume()
        #expect(try await resuming.settle(record) == .succeeded)
        #expect(resuming.sockets.sockets.count == 1)
    }

    /// A watch that stopped with an error keeps it when resuming again, since errors such as a rate limit aren't retried
    /// on their own; once a caller reads it, or a new connection replaces the watch, resuming watches the record again.
    @Test
    func `Resuming retries a failed watch only after its error is read or on a new connection`() async throws {
        let fixture = try SigningFixture()
        let record = try TransactionRecord.fixture(LocalSending.payment(), signature: "pending",
                                                   account: fixture.account.id)
        let sockets = SocketSequence()
        let coordinator = try LocalTransactions(fixture: fixture, statuses: [.status(.finalized)],
                                                sockets: sockets).coordinator
        let (attempts, attempted) = AsyncStream.makeStream(of: Void.self)
        var failures = 2
        // The first two watches fail at once, as they can't create the coordinator.
        let store = TransactionStore.inMemory([record.key: StoredValue([record])], pending: StoredValue([record.key])) {
            _ in
            attempted.yield()
            guard failures == 0 else {
                failures -= 1
                throw SubmitterError.noProviders
            }
            return coordinator
        }
        var attemptsMade = attempts.makeAsyncIterator()

        await store.resume()
        _ = await attemptsMade.next()
        await store.resume()

        await #expect(throws: SubmitterError.noProviders) { try await store.watch(record.id, for: record.key) }
        await store.resume()
        _ = await attemptsMade.next()
        await store.resume(replacingFailedWatches: true)
        #expect(await store.settledStatus(of: record) == .succeeded)
        await sockets.waitUntilClosed()
    }

    // MARK: Erasing

    /// Erasing stops the watches and deletes the pending index.
    @Test
    func `Erasing clears the index`() async throws {
        // The watch never settles: no status exists and the blockhash stays valid.
        let resuming = try LocalSending(statuses: [.status(nil)])
        _ = try await resuming.send()
        for await _ in resuming.sockets.openings { break }

        try await resuming.store.erase()

        await resuming.sockets.waitUntilClosed()
        #expect(await resuming.pending.value == nil)
    }

    /// Erasing an account removes its keys on every network from the pending index and keeps other accounts' keys.
    @Test
    func `Erasing an account removes only its keys from the index`() async throws {
        let (erased, kept) = (UUID(), UUID())
        let keptKey = TransactionRecord.Key(account: kept, network: .devnet)
        let pending = StoredValue<Set<TransactionRecord.Key>>([
            TransactionRecord.Key(account: erased, network: .devnet),
            TransactionRecord.Key(account: erased, network: .mainnet), keptKey,
        ])
        let store = TransactionStore.inMemory([:], pending: pending)

        try await store.erase(account: erased)

        #expect(await pending.value == [keptKey])
    }
}
