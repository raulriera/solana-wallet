import Foundation
import Storage
import Testing
import Transactions
@testable import RPC
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TransactionStoreResumptionTests {
    @Test
    func `Resuming watches the saved pending records of every account and network`() async throws {
        let records = [TransactionRecord.fixture(.payment, signature: "devnet", account: UUID()),
                       .fixture(.privateDeposit, signature: "mainnet", account: UUID(), network: .mainnet)]
        let resuming = try LocalSending(pending: StoredValue(records))

        await resuming.store.resume()

        for record in records {
            #expect(await resuming.store.settledStatus(of: record) == .succeeded(slot: 405))
        }
        #expect(await resuming.pending.value == [])
        await resuming.sockets.waitUntilClosed()
    }

    @Test
    func `Resuming starts no duplicate watches`() async throws {
        let fixture = try SigningFixture()
        let record = TransactionRecord.fixture(.payment, signature: "pending", account: fixture.account.id)
        let gate = Suspension()
        let resuming = try LocalSending(statusGate: gate, fixture: fixture, pending: StoredValue([record]))
        let store = resuming.store

        await withDiscardingTaskGroup { group in
            group.addTask { await store.resume() }
            group.addTask { await store.resume() }
        }
        await gate.waitUntilStarted()
        await store.resume()

        gate.resume()
        #expect(try await resuming.settle(record) == .succeeded(slot: 405))
        #expect(resuming.sockets.sockets.count == 1)
    }

    @Test
    func `Resuming retries a failed watch only after its error is read or on a new connection`() async throws {
        let fixture = try SigningFixture()
        let record = TransactionRecord.fixture(.payment, signature: "pending", account: fixture.account.id)
        let sockets = SocketSequence()
        let coordinator = try LocalTransactions(fixture: fixture, statuses: [.status(.finalized)],
                                                sockets: sockets).coordinator
        let (attempts, attempted) = AsyncStream.makeStream(of: Void.self)
        var failures = 2
        let store = TransactionStore.inMemory(StoredValue([record])) { _ in
            attempted.yield()
            guard failures == 0 else {
                failures -= 1
                throw TransactionCoordinatorError.unsupportedNetwork
            }
            return coordinator
        }
        var attemptsMade = attempts.makeAsyncIterator()

        await store.resume()
        _ = await attemptsMade.next()
        await store.resume()

        await #expect(throws: TransactionCoordinatorError.unsupportedNetwork) { try await store.watch(record.id, for: record.key) }
        await store.resume()
        _ = await attemptsMade.next()
        await store.resume(replacingFailedWatches: true)
        #expect(await store.settledStatus(of: record) == .succeeded(slot: 405))
        await sockets.waitUntilClosed()
    }
}
