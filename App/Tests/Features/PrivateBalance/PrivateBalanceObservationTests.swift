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
    @Test
    func `An active window reads the private balance`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]))
        let hosted = try HostedWindow(PrivateBalanceObservationRoot(store: store, account: account, scenePhase: .active))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        try await PrivateBalanceFixtures.status(of: account, in: store, becomes: .off(isRegistered: false))
    }

    @Test
    func `An active window polls the private balance`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let registry = try PrivateBalanceFixtures.registry(publishing: record.shieldedAccount(for: account.address))
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered, registry])
        let store = try PrivateBalanceStore.fixture(responses, keys: StoredValue([account.address.value: record]),
                                                    pollInterval: .milliseconds(10))
        let hosted = try HostedWindow(PrivateBalanceObservationRoot(store: store, account: account, scenePhase: .active))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        try await PrivateBalanceFixtures.status(of: account, in: store, becomes: .balance(available: 0, pending: 0))
    }

    @Test
    func `Pending SOL after a settled private move is read again quickly`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let sent = try PendingMove(from: account.id)
        let (store, notes) = try await PrivateBalanceFixtures.pendingDeposit(of: account,
                                                                             transactions: sent.transactions,
                                                                             pollInterval: .seconds(3_600),
                                                                             followUpInterval: .milliseconds(500))
        let hosted = try HostedWindow(PrivateBalanceObservationRoot(store: store, account: account, scenePhase: .active))
        defer { hosted.close() }
        try #require(try await hosted.appears())
        try await PrivateBalanceFixtures.status(of: account, in: store,
                                                becomes: .balance(available: 0, pending: 1_000_000))
        let balance = try #require(store.balance(for: account, on: .devnet))
        #expect(!balance.isFollowingUp)

        #expect(try await sent.settle() == .succeeded)

        for await isFollowingUp in Observations({ balance.isFollowingUp }) where isFollowingUp { break }
        try await notes.save([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        for await status in Observations({ balance.status }) where status == .balance(available: 0, pending: 0) { break }
        #expect(!balance.isFollowingUp)
    }

    @Test
    func `An inactive window reads nothing`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes()
        let store = try PrivateBalanceStore.fixture(responses)
        let providers = ProviderStore.inMemory()
        await providers.load()
        let hosted = try HostedWindow(PrivateBalanceObservationRoot(store: store, account: account, scenePhase: .background,
                                                                    providers: providers))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        #expect(store.balance(for: account, on: .devnet) == nil)
        #expect(await responses.requests.isEmpty)
    }
}
