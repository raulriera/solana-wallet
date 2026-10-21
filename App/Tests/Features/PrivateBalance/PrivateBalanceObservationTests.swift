import Observation
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
        let model = try PrivateBalanceModel.fixture(HTTPResponses.privateNotes())
        let hosted = try HostedWindow(PrivateBalanceObservationRoot(model: model, account: account, scenePhase: .active))
        defer { hosted.close() }
        // Closing the window before it finishes appearing would interrupt UIKit's appearance transition.
        try #require(try await hosted.appears())

        // The suite's time limit ends the wait if the window never reads the balance.
        for await status in Observations({ model.status }) where status != nil { break }
        #expect(model.status == .off)
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
