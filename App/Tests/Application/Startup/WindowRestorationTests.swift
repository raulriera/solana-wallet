import Observation
import RPC
import Testing
@testable import widgets

/// Runs a window's restoration in a real window, so a window that enters onboarding opens its next wallet on Mainnet
/// and its portfolio.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WindowRestorationTests {
    /// A devnet window on Settings that reconnects to find no saved wallet, as after another window's reset, returns
    /// to Mainnet and the portfolio.
    /// - Throws: A test prerequisite error.
    @Test
    func `A window that finds no saved wallet starts over on Mainnet and its portfolio`() async throws {
        let choices = WindowChoices(network: .devnet, section: .settings)
        let router = WindowRouter(initialDestination: .restoringWallets)
        let startup = WindowStartup(accounts: .inMemory(), router: router)
        let hosted = try HostedWindow(WindowRestorationRoot(choices: choices, startup: startup, router: router))
        defer { hosted.close() }
        // Closing the window before it finishes appearing would interrupt UIKit's appearance transition.
        try #require(try await hosted.appears())

        // The suite's time limit ends the wait if the window never returns to Mainnet.
        for await network in Observations({ choices.network }) where network == .mainnet { break }
        #expect(router.destination == .onboarding)
        #expect(choices.section == .portfolio)
    }

    /// A devnet window on Settings that a reset returns to onboarding opens its next wallet on Mainnet and the
    /// portfolio.
    /// - Throws: A test prerequisite error.
    @Test
    func `A reset starts the window's next wallet on Mainnet and its portfolio`() async throws {
        let account = try Account.fixture(index: 1)
        let choices = WindowChoices(network: .devnet, section: .settings)
        // A window that already shows a wallet keeps it, so startup changes nothing before the reset.
        let router = WindowRouter(initialDestination: .wallet(account))
        let startup = WindowStartup(accounts: .inMemory(StoredValue([account])), router: router)
        let hosted = try HostedWindow(WindowRestorationRoot(choices: choices, startup: startup, router: router))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        router.route(to: .onboarding)

        for await network in Observations({ choices.network }) where network == .mainnet { break }
        #expect(choices.section == .portfolio)
    }
}
