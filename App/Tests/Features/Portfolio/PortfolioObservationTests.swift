import Observation
import RPC
import SwiftUI
import Testing
import Transactions
@testable import widgets

/// Runs a window's portfolio observation in a real window, over the shared portfolios.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PortfolioObservationTests {
    /// An inactive scene observes nothing; the wallet's observation starts once the scene is active.
    /// - Throws: A test prerequisite error.
    @Test
    func `An inactive scene observes only once it's active`() async throws {
        let shown = ShownWallet(try Account.fixture(index: 1), phase: .inactive)
        let window = try await Window(showing: shown)
        defer { window.hosted.close() }
        #expect(await window.service.calls.isEmpty)

        shown.phase = .active

        // The suite's time limit ends each wait if the window never reaches that state.
        var requests = window.service.requests.makeAsyncIterator()
        let observation = try #require(await requests.next())
        #expect(observation.kind == .observation)
        #expect(observation.owner == shown.account.address.value)
    }

    /// Another network, as Settings switches to, ends the wallet's observation there and observes it on the new one.
    /// - Throws: A test prerequisite error.
    @Test
    func `Another network observes the wallet there instead`() async throws {
        let account = try Account.fixture(index: 1)
        try await expectReplacedObservation(of: account) { $0.network = .mainnet }
    }

    /// Another account ends the previous account's observation and observes the new account's wallet.
    /// - Throws: A test prerequisite error.
    @Test
    func `Another account observes its own wallet instead`() async throws {
        let other = try Account.fixture(index: 2)
        try await expectReplacedObservation(of: other) { $0.account = other }
    }

    /// A transaction of the window's account that settles reads the balances again, even without the review that sent
    /// it; nothing is read again before.
    /// - Throws: A fixture or test prerequisite error.
    @Test
    func `A settled transaction reads the balances again`() async throws {
        let account = try Account.fixture(index: 1)
        let sent = try PendingPayment(from: account.id)
        let window = try await Window(showing: ShownWallet(account), transactions: sent.transactions)
        defer { window.hosted.close() }
        var requests = window.service.requests.makeAsyncIterator()
        _ = try #require(await requests.next())
        // Only the observation so far: the balances aren't read again before the payment settles.
        #expect(await window.service.calls.map(\.kind) == [.observation])

        #expect(try await sent.settle() == .succeeded)

        let reload = try #require(await requests.next())
        #expect(reload.kind == .reload)
        #expect(reload.owner == account.address.value)
    }

    /// Checks that a change to the shown wallet ends the first observation and starts one for the new wallet.
    /// - Parameters:
    ///   - account: The account whose wallet the window observes after the change.
    ///   - change: Changes the shown wallet, as the window does for another account or network.
    /// - Throws: A test prerequisite error.
    private func expectReplacedObservation(of account: widgets.Account,
                                           after change: (ShownWallet) -> Void) async throws {
        let shown = ShownWallet(try Account.fixture(index: 1))
        let window = try await Window(showing: shown)
        defer { window.hosted.close() }
        var requests = window.service.requests.makeAsyncIterator()
        let first = try #require(await requests.next())

        change(shown)

        for await _ in first.termination {}
        let replacement = try #require(await requests.next())
        #expect(replacement.kind == .observation)
        #expect(replacement.owner == account.address.value)
    }

    /// A hosted window that observes the shown wallet over the shared portfolios, once it has appeared.
    @MainActor
    private struct Window {
        /// The portfolio service that the shared portfolios read through.
        let service = PortfolioResponses()
        let hosted: HostedWindow<PortfolioObservationRoot>

        /// Hosts the window and waits until it appears.
        /// - Parameters:
        ///   - shown: The wallet that the window shows.
        ///   - transactions: The shared transactions, whose settled payments read the balances again.
        /// - Throws: A test prerequisite error.
        init(showing shown: ShownWallet, transactions: TransactionStore = .unused) async throws {
            hosted = try HostedWindow(PortfolioObservationRoot(portfolios: .serving(service), shown: shown,
                                                               transactions: transactions))
            // Closing the window before it finishes appearing would interrupt UIKit's appearance transition.
            try #require(try await hosted.appears())
        }
    }
}
