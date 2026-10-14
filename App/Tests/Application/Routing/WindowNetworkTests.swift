import Observation
import RPC
import SwiftUI
import Testing
import Transactions
@testable import widgets

/// Runs the window's network lifecycle in a real window, so a change observes the new network and a reset returns the
/// window to Mainnet.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WindowNetworkTests {
    /// Choosing devnet stops observing the wallet on mainnet's portfolio and observes it on devnet's.
    /// - Throws: A test prerequisite error.
    @Test
    func `Choosing another network observes the wallet on that network's portfolio`() async throws {
        let account = try widgets.Account.fixture(index: 1)
        let owner: String? = account.address.value
        let choice = NetworkChoice(.mainnet)
        let portfolio = WindowPortfolio(network: .mainnet) { RecordingPortfolio(network: $0) }
        let mainnet = try #require(portfolio.coordinator as? RecordingPortfolio)
        let hosted = try HostedWindow(WindowNetworkRoot(choice: choice, portfolio: portfolio, account: account,
                                                        resetRevision: Revision(), providerRevision: Revision()))
        defer { hosted.close() }
        // Closing the window before it finishes appearing would interrupt UIKit's appearance transition.
        try #require(try await hosted.appears())
        // The suite's time limit ends each wait if the window never reaches that state.
        for await observing in Observations({ mainnet.isObserving }) where observing { break }

        choice.network = .devnet

        for await network in Observations({ portfolio.coordinator.network }) where network == .devnet { break }
        let devnet = try #require(portfolio.coordinator as? RecordingPortfolio)
        for await observing in Observations({ devnet.isObserving }) where observing { break }
        for await observing in Observations({ mainnet.isObserving }) where !observing { break }
        #expect(devnet.observedOwners == [owner])
        #expect(mainnet.observedOwners == [owner])
    }

    /// A reset in any window returns a devnet window to Mainnet, with mainnet's portfolio.
    /// - Throws: A test prerequisite error.
    @Test
    func `A reset returns the window to Mainnet`() async throws {
        let account = try widgets.Account.fixture(index: 1)
        let choice = NetworkChoice(.devnet)
        let portfolio = WindowPortfolio(network: .devnet) { RecordingPortfolio(network: $0) }
        let devnet = try #require(portfolio.coordinator as? RecordingPortfolio)
        let reset = Revision()
        let hosted = try HostedWindow(WindowNetworkRoot(choice: choice, portfolio: portfolio, account: account,
                                                        resetRevision: reset, providerRevision: Revision()))
        defer { hosted.close() }
        try #require(try await hosted.appears())
        // Observation starts once the window is on screen, where its lifecycle sees the reset.
        for await observing in Observations({ devnet.isObserving }) where observing { break }

        reset.advance()

        for await network in Observations({ portfolio.coordinator.network }) where network == .mainnet { break }
        #expect(choice.network == .mainnet)
    }
}
