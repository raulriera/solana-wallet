import Observation
import Privacy
import RPC
import SwiftUI
import Testing
import Transactions
@testable import widgets

/// Runs a window's private-balance reads in a real window.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PrivateBalanceObservationTests {
    /// An active window reads its account's private balance.
    /// - Throws: A fixture or test prerequisite error.
    @Test
    func `An active window reads the private balance`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes(registry: [PrivateBalanceFixtures.unregistered]))
        let hosted = try HostedWindow(PrivateBalanceObservationRoot(model: model, account: account, scenePhase: .active))
        defer { hosted.close() }
        // Closing the window before it finishes appearing would interrupt UIKit's appearance transition.
        try #require(try await hosted.appears())

        // The suite's time limit ends the wait if the window never reads the balance.
        for await status in Observations({ model.status }) where status != nil { break }
        #expect(model.status == .off(isRegistered: false))
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
        let model = try PrivateBalanceModel.fixture(responses, keys: StoredValue([account.address.value: record]))
        let hosted = try HostedWindow(PrivateBalanceObservationRoot(model: model, account: account, scenePhase: .active,
                                                                    pollInterval: .milliseconds(10)))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        // The suite's time limit ends the wait if no poll reads the balance.
        for await status in Observations({ model.status }) where status == .balance(available: 0, pending: 0) { break }
        #expect(model.status == .balance(available: 0, pending: 0))
    }

    /// A settled private move starts the reads again at once, and pending SOL then follows up quickly, so it turns
    /// available without waiting for the next poll.
    /// - Throws: A fixture or test prerequisite error.
    @Test
    func `Pending SOL after a settled private move is read again quickly`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let sent = try PendingMove(from: account.id)
        let (model, notes) = try await PrivateBalanceFixtures.pendingDeposit(of: account,
                                                                             transactions: sent.transactions)
        // Ordinary polls never come within the suite's time limit, so only a follow-up reads the balance again.
        let hosted = try HostedWindow(PrivateBalanceObservationRoot(model: model, account: account, scenePhase: .active,
                                                                    pollInterval: .seconds(3_600),
                                                                    followUpInterval: .milliseconds(10)))
        defer { hosted.close() }
        try #require(try await hosted.appears())
        for await status in Observations({ model.status }) where status != nil { break }
        #expect(!model.isFollowingUp)

        #expect(try await sent.settle() == .succeeded)

        // The suite's time limit ends each wait if no follow-up reads the balance.
        for await left in Observations({ model.followUpReadsLeft })
        where left > 0 && left < PrivateBalanceModel.followUpReads { break }
        // The indexer reports the deposit, so nothing is pending.
        try await notes.save([PrivateBalances.noteID(of: account, on: .devnet): NoteSyncState()])
        for await status in Observations({ model.status }) where status == .balance(available: 0, pending: 0) { break }
        #expect(!model.isFollowingUp)
    }

    /// A window in the background reads nothing.
    /// - Throws: A fixture or test prerequisite error.
    @Test
    func `An inactive window reads nothing`() async throws {
        let account = try await PrivateBalanceFixtures.account()
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes())
        let hosted = try HostedWindow(PrivateBalanceObservationRoot(model: model, account: account, scenePhase: .background))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        // An observation that ran would have chosen the account, so this refresh would read its balance.
        await model.refresh()

        #expect(model.status == nil)
    }
}
