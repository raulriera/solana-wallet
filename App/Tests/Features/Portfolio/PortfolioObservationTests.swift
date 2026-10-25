import Observation
import Testing
import Transactions
@testable import widgets

/// Runs a window's portfolio observation in a real window, so a replaced portfolio takes over the observation.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PortfolioObservationTests {
    /// Replacing mainnet's portfolio with devnet's, as a network change does, stops observing the wallet on mainnet's
    /// and observes it on devnet's.
    /// - Throws: A test prerequisite error.
    @Test
    func `A replaced portfolio observes the wallet instead of the previous one`() async throws {
        let account = try Account.fixture(index: 1)
        let owner: String? = account.address.value
        let mainnet = RecordingPortfolio()
        let devnet = RecordingPortfolio()
        let shown = ShownPortfolio(mainnet)
        let hosted = try HostedWindow(PortfolioObservationRoot(shown: shown, account: account))
        defer { hosted.close() }
        // Closing the window before it finishes appearing would interrupt UIKit's appearance transition.
        try #require(try await hosted.appears())
        // The suite's time limit ends each wait if the window never reaches that state.
        for await observing in Observations({ mainnet.isObserving }) where observing { break }

        shown.coordinator = devnet

        for await observing in Observations({ devnet.isObserving }) where observing { break }
        for await observing in Observations({ mainnet.isObserving }) where !observing { break }
        #expect(devnet.observedOwners == [owner])
        #expect(mainnet.observedOwners == [owner])
    }

    /// A transaction of the window's account that settles reads the balances again, even without the review that sent
    /// it; nothing is read again before.
    /// - Throws: A fixture or test prerequisite error.
    @Test
    func `A settled transaction reads the balances again`() async throws {
        let account = try Account.fixture(index: 1)
        let portfolio = RecordingPortfolio()
        let sent = try PendingPayment(from: account.id)
        let hosted = try HostedWindow(PortfolioObservationRoot(shown: ShownPortfolio(portfolio), account: account,
                                                               transactions: sent.transactions))
        defer { hosted.close() }
        try #require(try await hosted.appears())
        for await observing in Observations({ portfolio.isObserving }) where observing { break }
        #expect(portfolio.refreshes == 0)

        #expect(try await sent.settle() == .succeeded)

        // The suite's time limit ends the wait if the balances are never read again.
        for await refreshes in Observations({ portfolio.refreshes }) where refreshes == 1 { break }
    }
}
