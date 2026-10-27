import Observation
import RPC
import Testing
import Transactions
@testable import Portfolio
@testable import widgets

/// Exercises one window's view of the shared portfolios: its wallet and its observation.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PortfolioCoordinatorTests {
    /// Verifies an inactive scene or missing selection never starts work.
    @Test(arguments: [false, true])
    /// - Throws: A fixture error.
    func `Inactive and unselected portfolios do not request data`(isActive: Bool) async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(store: .serving(service), network: .devnet)
        await coordinator.observe(for: isActive ? nil : try Account.fixture(index: 1), isActive: isActive)
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
        let wallet = try Account.fixture(index: 1)
        let other = try Account.fixture(index: 2)
        let first = Task { await coordinator.observe(for: wallet, isActive: true) }
        defer { first.cancel() }
        let old = try #require(await requests.next())
        let cached = Snapshot.fixture(owner: wallet.address.value, lamports: 1)
        old.continuation.yield(Update(snapshot: cached, phase: .ready, revision: 8))
        await waitForSnapshot(cached, in: coordinator)

        // A new wallet restarts the window's view task, which cancels the previous one.
        first.cancel()
        await first.value
        let second = Task { await coordinator.observe(for: other, isActive: true) }
        defer { second.cancel() }
        let current = try #require(await requests.next())
        #expect(coordinator.update == nil)
        for await _ in old.termination {}
        let replacement = Snapshot.fixture(owner: other.address.value, lamports: 2)
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
        let account = try Account.fixture(index: 1)
        var coordinator: (any PortfolioCoordinating)? = PortfolioCoordinator(store: store, network: .devnet)
        weak let released = coordinator
        var requests = service.requests.makeAsyncIterator()
        var viewing: Task<Void, Never>? = Task { [coordinator] in
            await coordinator?.observe(for: account, isActive: true)
        }
        let observation = try #require(await requests.next())
        viewing?.cancel()
        await viewing?.value
        for await _ in observation.termination {}
        viewing = nil
        coordinator = nil
        #expect(released == nil)
    }

    /// Awaits observable snapshot publication without sleeps or polling.
    /// - Parameters:
    ///   - expected: The snapshot that must reach presentation state.
    ///   - coordinator: The presentation under test.
    private func waitForSnapshot(_ expected: Snapshot, in coordinator: PortfolioCoordinator) async {
        for await snapshot in Observations({ coordinator.update?.snapshot }) where snapshot == expected { return }
    }
}
