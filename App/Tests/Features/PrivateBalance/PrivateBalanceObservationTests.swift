import Observation
import Privacy
import RPC
import SwiftUI
import Testing
import Transactions
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PrivateBalanceObservationTests {
    @Test(arguments: [ScenePhase.active, .inactive])
    func `A foreground window polls the private balance`(phase: ScenePhase) async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let registry = try PrivateBalanceFixtures.registry(publishing: record.shieldedAccount(for: account.address))
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered, registry])
        let clock = ManualClock()
        var waits = clock.waits.makeAsyncIterator()
        let store = try PrivateBalanceStore.fixture(responses, keys: StoredValue([account.address.value: record]),
                                                    clock: clock)
        let hosted = try HostedWindow(PrivateBalanceObservationRoot(store: store, account: account, scenePhase: phase))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        #expect(try await clock.advanceToNextWait(&waits) == .seconds(30))

        try await PrivateBalanceFixtures.status(of: account, in: store, becomes: .balance(available: 0, pending: 0, of: .nativeSOL))
    }

    @Test
    func `Pending SOL after a settled private move is read again quickly`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let sent = try PendingMove(from: account.id)
        let clock = ManualClock()
        var waits = clock.waits.makeAsyncIterator()
        let (store, notes) = try await PrivateBalanceFixtures.pendingDeposit(of: account,
                                                                             transactions: sent.transactions,
                                                                             clock: clock)
        let hosted = try HostedWindow(PrivateBalanceObservationRoot(store: store, account: account, scenePhase: .active))
        defer { hosted.close() }
        try #require(try await hosted.appears())
        try await PrivateBalanceFixtures.status(of: account, in: store,
                                                becomes: .balance(available: 0, pending: 1_000_000, of: .nativeSOL))
        let balance = try #require(store.balance(for: account, on: .devnet))
        #expect(!balance.isFollowingUp)
        #expect(try await clock.durationToNextWait(&waits) == .seconds(30))

        #expect(try await sent.settle() == .succeeded)

        for await isFollowingUp in Observations({ balance.isFollowingUp }) where isFollowingUp { break }
        try await notes.save([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        #expect(try await clock.advanceToNextWait(&waits) == .seconds(3))
        for await status in Observations({ balance.status }) where status == .balance(available: 0, pending: 0, of: .nativeSOL) { break }
        #expect(!balance.isFollowingUp)
    }

    @Test
    func `A background window reads nothing`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes()
        let store = try PrivateBalanceStore.fixture(responses)
        let rpcStore = RPCStore.inMemory()
        await rpcStore.load()
        let hosted = try HostedWindow(PrivateBalanceObservationRoot(store: store, account: account, scenePhase: .background,
                                                                    rpcStore: rpcStore))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        #expect(store.balance(for: account, on: .devnet) == nil)
        #expect(await responses.requests.isEmpty)
    }
}
