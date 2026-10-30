import Observation
import RPC
import Testing
@testable import widgets

/// Runs a window's restoration in a real window, so a window keeps the account it shows and a window that enters
/// onboarding opens its next wallet on Mainnet and its portfolio.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WindowRestorationTests {
    /// A devnet window on Settings that reconnects to find no saved wallet, as after another window's reset, returns
    /// to Mainnet and the portfolio.
    /// - Throws: A test prerequisite error.
    @Test
    func `A window that finds no saved wallet starts over on Mainnet and its portfolio`() async throws {
        let choices = WindowChoices(network: .devnet, section: .settings)
        let window = WindowModel(accounts: .inMemory())
        let hosted = try HostedWindow(WindowRestorationRoot(choices: choices, window: window))
        defer { hosted.close() }
        // Closing the window before it finishes appearing would interrupt UIKit's appearance transition.
        try #require(try await hosted.appears())

        // The suite's time limit ends the wait if the window never returns to Mainnet.
        for await network in Observations({ choices.network }) where network == .mainnet { break }
        #expect(window.destination == .onboarding)
        #expect(choices.section == .portfolio)
    }

    /// A devnet window on Settings that a reset returns to onboarding opens its next wallet on Mainnet and the
    /// portfolio, and only in the window that saves it.
    /// - Throws: A test prerequisite error.
    @Test
    func `A reset starts the window's next wallet on Mainnet and its portfolio`() async throws {
        let account = try Account.fixture(index: 1)
        let accounts = AccountStore.inMemory(StoredValue([account]))
        let choices = WindowChoices(network: .devnet, section: .settings)
        let window = WindowModel(accounts: accounts)
        let hosted = try HostedWindow(WindowRestorationRoot(choices: choices, window: window))
        defer { hosted.close() }
        try #require(try await hosted.appears())
        for await destination in Observations({ window.destination }) where destination == .wallet(account) { break }

        try await accounts.erase()

        for await network in Observations({ choices.network }) where network == .mainnet { break }
        #expect(choices.section == .portfolio)
        try await accounts.add(.fixture(index: 2))
        #expect(window.destination == .onboarding)
    }

    /// A window whose account another window deletes chooses its wallet's first account, so it reopens that account.
    /// - Throws: A test prerequisite error.
    @Test
    func `A window whose account is deleted chooses its wallet's first account`() async throws {
        let walletFirst = try Account.fixture(index: 0)
        let deleted = try Account.fixture(index: 1, recoveryID: walletFirst.recoveryID)
        let accounts = AccountStore.inMemory(StoredValue([walletFirst, deleted]))
        let window = WindowModel(accounts: accounts)
        window.account = deleted
        let hosted = try HostedWindow(WindowRestorationRoot(choices: WindowChoices(network: .mainnet, section: .portfolio),
                                                            window: window))
        defer { hosted.close() }
        try #require(try await hosted.appears())
        for await destination in Observations({ window.destination }) where destination == .wallet(deleted) { break }

        try await accounts.remove(deleted.id)

        for await selection in Observations({ window.selection }) where selection == .init(walletFirst) { break }
        #expect(window.destination == .wallet(walletFirst))
    }
}
