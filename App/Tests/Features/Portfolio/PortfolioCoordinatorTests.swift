import Foundation
import Observation
import RPC
import Testing
import Transactions
@testable import Portfolio
@testable import widgets

/// Exercises one window's view of the shared portfolios: its wallet, its observation, and its token lists.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PortfolioCoordinatorTests {
    /// BONK's mainnet mint address, a public token.
    private static let bonk = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"

    /// Verifies an added token is saved to the selected wallet's list.
    /// - Throws: A storage or test prerequisite error.
    @Test
    func `Adding a token saves it to the selected wallet's list`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = PortfolioCoordinator(store: .serving(filePortfolio(in: directory)), network: .mainnet)
        let bonk = ListedToken(mint: try Address(Self.bonk), program: .token, decimals: 5, symbol: "Bonk", name: "Bonk")

        await coordinator.observe(for: PublicWallet.address, isActive: false)
        try await coordinator.add(bonk)

        #expect(try savedList(in: directory)?.tokens.last == bonk)
    }

    /// Verifies a removed token leaves the selected wallet's saved list.
    /// - Throws: A storage or test prerequisite error.
    @Test
    func `Removing a token saves the selected wallet's list without it`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = PortfolioCoordinator(store: .serving(filePortfolio(in: directory)), network: .mainnet)

        await coordinator.observe(for: PublicWallet.address, isActive: false)
        try await coordinator.remove(Address(DefaultToken.usdt.rawValue))

        #expect(try savedList(in: directory)?.tokens.map(\.mint.value) == [DefaultToken.usdc.rawValue])
    }

    /// Verifies an inactive scene or missing selection never starts work.
    @Test(arguments: [false, true])
    func `Inactive and unselected portfolios do not request data`(isActive: Bool) async {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(store: .serving(service), network: .devnet)
        await coordinator.observe(for: isActive ? nil : "wallet-a", isActive: isActive)
        await coordinator.refresh()
        #expect(coordinator.update == nil)
        #expect(await service.calls.isEmpty)
    }

    /// Verifies another wallet shows its own data, and the previous wallet's observation ends with the window's task.
    /// - Throws: A test prerequisite error.
    @Test
    func `Switching wallets shows the other wallet and ends the first one's observation`() async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(store: .serving(service), network: .devnet)
        var requests = service.requests.makeAsyncIterator()
        let first = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { first.cancel() }
        let old = try #require(await requests.next())
        let cached = Snapshot.fixture(owner: "wallet-a", lamports: 1)
        old.continuation.yield(Update(snapshot: cached, phase: .ready, revision: 8))
        await waitForSnapshot(cached, in: coordinator)

        // A new wallet restarts the window's view task, which cancels the previous one.
        first.cancel()
        await first.value
        let second = Task { await coordinator.observe(for: "wallet-b", isActive: true) }
        defer { second.cancel() }
        let current = try #require(await requests.next())
        #expect(coordinator.update == nil)
        for await _ in old.termination {}
        let replacement = Snapshot.fixture(owner: "wallet-b", lamports: 2)
        current.continuation.yield(Update(snapshot: replacement, phase: .ready, revision: 11))
        await waitForSnapshot(replacement, in: coordinator)
        #expect(coordinator.holdings.map(\.id) == [.nativeSOL])
        second.cancel()
        await second.value

        await coordinator.observe(for: nil, isActive: true)
        #expect(coordinator.update == nil)
        #expect(coordinator.holdings.isEmpty)
    }

    /// Verifies view task cancellation ends observation and permits coordinator deallocation.
    /// - Throws: A test prerequisite error.
    @Test
    func `View cancellation releases observation and presentation state`() async throws {
        let service = PortfolioResponses()
        let store = PortfolioStore.serving(service)
        var coordinator: (any PortfolioCoordinating)? = PortfolioCoordinator(store: store, network: .devnet)
        weak let released = coordinator
        var requests = service.requests.makeAsyncIterator()
        var viewing: Task<Void, Never>? = Task { [coordinator] in
            await coordinator?.observe(for: "wallet-a", isActive: true)
        }
        let observation = try #require(await requests.next())
        viewing?.cancel()
        await viewing?.value
        for await _ in observation.termination {}
        viewing = nil
        coordinator = nil
        #expect(released == nil)
    }

    /// Creates a portfolio service that keeps its token lists and snapshots in a test's directory.
    /// - Parameter directory: The test's private directory.
    /// - Returns: A mainnet service that makes no requests for token-list edits.
    private func filePortfolio(in directory: URL) -> Portfolio {
        Portfolio(rpc: Solana(network: .mainnet), store: FileSnapshotStore(directory: directory),
                  tokenLists: tokenLists(in: directory))
    }

    /// Reads the public wallet's saved token list from a test's directory.
    /// - Parameter directory: The test's private directory.
    /// - Returns: The saved list, or `nil` before anything is saved.
    /// - Throws: ``TokenListError/unreadable`` if the saved list can't be read.
    private func savedList(in directory: URL) throws -> Portfolio::TokenList? {
        try tokenLists(in: directory).tokenList(for: CacheKey(owner: PublicWallet.address, network: .mainnet))
    }

    /// Creates the token-list store in a test's directory.
    /// - Parameter directory: The test's private directory.
    /// - Returns: The store that the test's portfolio saves lists in.
    private func tokenLists(in directory: URL) -> FileTokenListStore {
        FileTokenListStore(directory: directory.appendingPathComponent("TokenLists"))
    }

    /// Awaits observable snapshot publication without sleeps or polling.
    /// - Parameters:
    ///   - expected: The snapshot that must reach presentation state.
    ///   - coordinator: The presentation under test.
    private func waitForSnapshot(_ expected: Snapshot, in coordinator: any PortfolioCoordinating) async {
        for await snapshot in Observations({ coordinator.update?.snapshot }) where snapshot == expected { return }
    }
}
