import Observation
import Privacy
import RPC
import SwiftUI
import Testing
import Transactions
@testable import widgets

/// Runs a window's private-balance reads through the shared store in a real window.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PrivateBalanceObservationTests {
    /// An active window reads its account's private balance.
    /// - Throws: A fixture or test prerequisite error.
    @Test
    func `An active window reads the private balance`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let store = try PrivateBalanceStore.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]))
        let hosted = try HostedWindow(PrivateBalanceObservationRoot(store: store, account: account, scenePhase: .active))
        defer { hosted.close() }
        // Closing the window before it finishes appearing would interrupt UIKit's appearance transition.
        try #require(try await hosted.appears())

        // The suite's time limit ends the wait if the window never reads the balance.
        try await PrivateBalanceFixtures.status(of: account, in: store, becomes: .off(isRegistered: false))
    }

    /// While private balances are on, an active window polls the balance, so a later change shows without a refresh.
    /// - Throws: A fixture or test prerequisite error.
    @Test
    func `An active window polls the private balance`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let record = try await PrivateBalanceFixtures.keys(for: account)
        let registry = try PrivateBalanceFixtures.registry(publishing: record.shieldedAccount(for: account.address))
        // The first read finds the account unregistered; a poll then finds it registered with an empty balance.
        let responses = HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered, registry])
        let store = try PrivateBalanceStore.fixture(responses, keys: StoredValue([account.address.value: record]),
                                                    pollInterval: .milliseconds(10))
        let hosted = try HostedWindow(PrivateBalanceObservationRoot(store: store, account: account, scenePhase: .active))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        // The suite's time limit ends the wait if no poll reads the balance.
        try await PrivateBalanceFixtures.status(of: account, in: store, becomes: .balance(available: 0, pending: 0))
    }

    /// A settled private move starts the reads again at once, and pending SOL then follows up quickly, so it turns
    /// available without waiting for the next poll.
    /// - Throws: A fixture or test prerequisite error.
    @Test
    func `Pending SOL after a settled private move is read again quickly`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let sent = try PendingMove(from: account.id)
        // Ordinary polls never come within the suite's time limit, so only a follow-up reads the balance again. The
        // follow-up's reads last several seconds, so the test changes the notes before they run out.
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

        // The suite's time limit ends each wait if the follow-up doesn't start or no follow-up reads the balance.
        for await isFollowingUp in Observations({ balance.isFollowingUp }) where isFollowingUp { break }
        // The indexer reports the deposit, so nothing is pending.
        try await notes.save([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        for await status in Observations({ balance.status }) where status == .balance(available: 0, pending: 0) { break }
        #expect(!balance.isFollowingUp)
    }

    /// A window in the background reads nothing.
    /// - Throws: A fixture or test prerequisite error.
    @Test
    func `An inactive window reads nothing`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let responses = HTTPResponses.privateNotes()
        let store = try PrivateBalanceStore.fixture(responses)
        // Read settings leave only the scene phase to keep the window from reading.
        let providers = ProviderStore.inMemory()
        await providers.load()
        let hosted = try HostedWindow(PrivateBalanceObservationRoot(store: store, account: account, scenePhase: .background,
                                                                    providers: providers))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        // An observation that ran would have created the account's balance.
        #expect(store.balance(for: account, on: .devnet) == nil)
        #expect(await responses.requests.isEmpty)
    }
}
