import Observation
import RPC
import Testing
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WindowRestorationTests {
    @Test
    func `A window that finds no saved wallet starts over on Mainnet and its portfolio`() async throws {
        let choices = WindowChoices(network: .devnet, section: .settings)
        let window = WindowModel(accounts: .inMemory())
        let hosted = try HostedWindow(WindowRestorationRoot(choices: choices, window: window))
        defer { hosted.close() }
        try #require(try await hosted.appears())

        for await network in Observations({ choices.network }) where network == .mainnet { break }
        #expect(window.destination == .onboarding)
        #expect(choices.section == .portfolio)
    }

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

    @Test
    func `A window whose account is deleted chooses the first saved account`() async throws {
        let first = try Account.fixture(index: 0)
        let deleted = try Account.fixture(index: 1)
        let accounts = AccountStore.inMemory(StoredValue([first, deleted]))
        let window = WindowModel(accounts: accounts)
        window.account = deleted
        let hosted = try HostedWindow(WindowRestorationRoot(choices: WindowChoices(network: .mainnet, section: .portfolio),
                                                            window: window))
        defer { hosted.close() }
        try #require(try await hosted.appears())
        for await destination in Observations({ window.destination }) where destination == .wallet(deleted) { break }

        try await accounts.remove(deleted.id)

        for await accountID in Observations({ window.accountID }) where accountID == first.id { break }
        #expect(window.destination == .wallet(first))
    }
}
