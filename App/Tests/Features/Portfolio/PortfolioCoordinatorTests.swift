import Foundation
import Observation
@testable import Portfolio
import RPC
import Testing
import Transactions
@testable import widgets

/// Exercises the view lifetime separately from the framework's network behavior.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PortfolioCoordinatorTests {
    /// BONK's mainnet mint address, a public token.
    private static let bonk = "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"

    /// Verifies a clock correction cannot reject newer balances for a large portfolio.
    @Test
    func `Clock rollback still displays the next complete 500-token portfolio`() async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        let before = largeSnapshot(time: 200, units: 10)
        observation.continuation.yield(Update(snapshot: before, phase: .ready, revision: 1))
        await waitForSnapshot(before, in: coordinator)
        let refreshing = Task { await coordinator.refresh() }
        defer { refreshing.cancel() }
        let reload = try #require(await requests.next())
        let after = largeSnapshot(time: 190, units: 20)
        reload.continuation.yield(Update(snapshot: after, phase: .ready, revision: 2))
        reload.continuation.finish()
        await refreshing.value
        #expect(coordinator.update?.snapshot == after)
        #expect(coordinator.update?.holdings.first?.amount?.units == 20)
        #expect(coordinator.update?.holdings.count == 500)
        viewing.cancel()
        await viewing.value
    }

    /// Verifies a delayed success cannot erase a failure from a subsequent operation.
    /// - Parameter hasNewHoldings: Whether the delayed success also carries more recent holdings.
    @Test(arguments: [false, true])
    func `Delayed ready state cannot clear a newer refresh error`(hasNewHoldings: Bool) async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        let cached = snapshot(owner: "wallet-a", revision: 1)
        observation.continuation.yield(Update(snapshot: cached, phase: .ready, revision: 3))
        await waitForSnapshot(cached, in: coordinator)
        let refreshing = Task { await coordinator.refresh() }
        defer { refreshing.cancel() }
        let reload = try #require(await requests.next())
        let holdings = hasNewHoldings ? snapshot(owner: "wallet-a", revision: 2) : cached
        let delayed = Update(snapshot: holdings, phase: .ready, revision: 4,
                             snapshotRevision: hasNewHoldings ? 4 : 3)
        let error = RPCError.http(statusCode: 429, retryAfter: "3")
        observation.continuation.yield(Update(snapshot: cached, phase: .failed(error), revision: 5, snapshotRevision: 3))
        for await failed in Observations({ coordinator.update?.error != nil }) {
            if failed { break }
        }
        reload.continuation.yield(delayed)
        reload.continuation.finish()
        await refreshing.value
        #expect(coordinator.update?.error as? RPCError == error)
        #expect(coordinator.update?.snapshot == holdings)
        viewing.cancel()
        await viewing.value
    }

    /// Builds a large deterministic portfolio with an independently controlled retrieval time.
    /// - Parameters:
    ///   - time: The device wall-clock value at retrieval.
    ///   - units: The amount held for each token.
    /// - Returns: Five hundred fungible holdings.
    private func largeSnapshot(time: TimeInterval, units: UInt64) -> Snapshot {
        Snapshot(owner: "wallet-a", network: .devnet, holdings: (0..<500).map {
            Holding(id: .asset("asset-\($0)"), amount: Amount(units: units, decimals: 6),
                    name: "Token \($0)", symbol: "T\($0)", imageURL: nil, valuation: nil)
        }, fetchedAt: Date(timeIntervalSince1970: time))
    }

    /// Verifies an added token is saved to the selected wallet's list.
    /// - Throws: A storage or test prerequisite error.
    @Test
    func `Adding a token saves it to the selected wallet's list`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = filePortfolio(in: directory)
        let coordinator = PortfolioCoordinator(service: service)
        let bonk = ListedToken(mint: try Address(Self.bonk), program: .token, decimals: 5, symbol: "Bonk", name: "Bonk")

        await coordinator.observe(for: PublicWallet.address, isActive: false)
        try await coordinator.add(bonk)

        #expect(try await service.tokenList(for: PublicWallet.address).tokens.last == bonk)
    }

    /// Verifies a removed token leaves the selected wallet's saved list.
    /// - Throws: A storage or test prerequisite error.
    @Test
    func `Removing a token saves the selected wallet's list without it`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = filePortfolio(in: directory)
        let coordinator = PortfolioCoordinator(service: service)

        await coordinator.observe(for: PublicWallet.address, isActive: false)
        try await coordinator.remove(Address(DefaultToken.usdt.rawValue))

        #expect(try await service.tokenList(for: PublicWallet.address).tokens.map(\.mint.value) == [DefaultToken.usdc.rawValue])
    }

    /// Verifies an inactive scene or missing selection never starts work.
    @Test(arguments: [false, true])
    func `Inactive and unselected portfolios do not request data`(isActive: Bool) async {
        let service = PortfolioResponses()
        let coordinator: any PortfolioCoordinating = PortfolioCoordinator(service: service)
        await coordinator.observe(for: isActive ? nil : "wallet-a", isActive: isActive)
        await coordinator.refresh()
        #expect(coordinator.update == nil)
        #expect(await service.calls.isEmpty)
    }

    /// Verifies backgrounding retains holdings, cancels both operations, and reopening observes again.
    @Test
    func `Background stops work and foreground reopens the selected wallet`() async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        #expect(observation.kind == .observation)
        let cached = snapshot(owner: "wallet-a", revision: 1)
        observation.continuation.yield(Update(snapshot: cached, phase: .ready, revision: 6))
        await waitForSnapshot(cached, in: coordinator)

        let refreshing = Task { await coordinator.refresh() }
        defer { refreshing.cancel() }
        let reload = try #require(await requests.next())
        reload.continuation.yield(Update(snapshot: cached, phase: .refreshing, revision: 7))
        await waitForProgress(in: coordinator)

        await coordinator.observe(for: "wallet-a", isActive: false)
        await viewing.value
        await refreshing.value
        for await _ in observation.termination {}
        for await _ in reload.termination {}
        #expect(coordinator.update?.snapshot == cached)
        #expect(coordinator.update?.isRefreshing == false)
        await coordinator.refresh()
        #expect(await service.calls.count == 2)

        let reopened = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { reopened.cancel() }
        let resumed = try #require(await requests.next())
        #expect(resumed.owner == "wallet-a")
        #expect(resumed.kind == .observation)
        #expect(coordinator.update?.snapshot == cached)
        // Another consumer can keep the shared refresh alive while this view is away.
        resumed.continuation.yield(Update(snapshot: cached, phase: .refreshing, revision: 7))
        await waitForProgress(in: coordinator)
        #expect(coordinator.update?.isRefreshing == true)
        reopened.cancel()
        await reopened.value
    }

    /// Verifies selection changes clear old holdings and obsolete cleanup cannot stop the replacement.
    @Test
    func `Switching wallets clears displayed data and cancels old work`() async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let first = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { first.cancel() }
        let old = try #require(await requests.next())
        let cached = snapshot(owner: "wallet-a", revision: 1)
        old.continuation.yield(Update(snapshot: cached, phase: .ready, revision: 8))
        await waitForSnapshot(cached, in: coordinator)
        let refreshing = Task { await coordinator.refresh() }
        defer { refreshing.cancel() }
        let reload = try #require(await requests.next())

        let second = Task { await coordinator.observe(for: "wallet-b", isActive: true) }
        defer { second.cancel() }
        let current = try #require(await requests.next())
        #expect(coordinator.update == nil)
        await first.value
        await refreshing.value
        for await _ in old.termination {}
        for await _ in reload.termination {}
        old.continuation.yield(Update(snapshot: cached, phase: .ready, revision: 9))
        reload.continuation.yield(Update(snapshot: cached, phase: .ready, revision: 10))
        let replacement = snapshot(owner: "wallet-b", revision: 2)
        current.continuation.yield(Update(snapshot: replacement, phase: .ready, revision: 11))
        await waitForSnapshot(replacement, in: coordinator)
        second.cancel()
        await second.value
        #expect(coordinator.update?.snapshot == replacement)

        await coordinator.observe(for: nil, isActive: true)
        #expect(coordinator.update == nil)
    }

    /// Verifies holdings follow each new snapshot in display order and leave with their wallet.
    @Test
    func `Holdings follow the latest snapshot in display order`() async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        let first = pricedSnapshot(["low": 1, "high": 5])
        observation.continuation.yield(Update(snapshot: first, phase: .ready, revision: 1))
        await waitForSnapshot(first, in: coordinator)
        #expect(coordinator.holdings.map(\.id) == [.asset("high"), .asset("low"), .nativeSOL])

        let second = pricedSnapshot(["low": 9, "high": 5])
        observation.continuation.yield(Update(snapshot: second, phase: .ready, revision: 2))
        await waitForSnapshot(second, in: coordinator)
        #expect(coordinator.holdings.map(\.id) == [.asset("low"), .asset("high"), .nativeSOL])

        viewing.cancel()
        await viewing.value
        await coordinator.observe(for: "wallet-b", isActive: false)
        #expect(coordinator.holdings.isEmpty)
    }

    /// Verifies a cancelled provider setup cannot deliver buffered data or stop a newer session.
    @Test
    func `Late registration from a cancelled session cannot publish`() async throws {
        let gate = PortfolioResponses.Registration()
        let service = PortfolioResponses(registration: gate)
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let first = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { first.cancel() }
        let old = try #require(await requests.next())
        old.continuation.yield(Update(snapshot: snapshot(owner: "wallet-a", revision: 99), phase: .ready, revision: 12))

        let second = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { second.cancel() }
        let current = try #require(await requests.next())
        let expected = snapshot(owner: "wallet-a", revision: 2)
        current.continuation.yield(Update(snapshot: expected, phase: .ready, revision: 13))
        await gate.release()
        await first.value
        await waitForSnapshot(expected, in: coordinator)
        second.cancel()
        await second.value
        #expect(coordinator.update?.snapshot == expected)
    }

    /// Verifies view task cancellation ends observation and permits coordinator deallocation.
    @Test
    func `View cancellation releases observation and presentation state`() async throws {
        let service = PortfolioResponses()
        var coordinator: PortfolioCoordinator? = PortfolioCoordinator(service: service)
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

    /// Verifies pull-to-refresh awaits a forced reload and observation remains usable afterward.
    @Test
    func `Pull to refresh forces a reload and preserves observation`() async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        let refreshing = Task { await coordinator.refresh() }
        defer { refreshing.cancel() }
        let reload = try #require(await requests.next())
        #expect(reload.owner == "wallet-a")
        #expect(reload.kind == .refresh(.reload))
        let refreshed = snapshot(owner: "wallet-a", revision: 2)
        reload.continuation.yield(Update(snapshot: refreshed, phase: .ready, revision: 14))
        reload.continuation.finish()
        await refreshing.value
        #expect(coordinator.update?.snapshot == refreshed)

        let changed = snapshot(owner: "wallet-a", revision: 3)
        observation.continuation.yield(Update(snapshot: changed, phase: .ready, revision: 15))
        await waitForSnapshot(changed, in: coordinator)
        viewing.cancel()
        await viewing.value
        #expect(await service.calls.count == 2)
    }

    /// Verifies cancelling a manual refresh does not cancel finalized-change observation.
    @Test
    func `Cancelling pull to refresh leaves observation active`() async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        let refreshing = Task { await coordinator.refresh() }
        let reload = try #require(await requests.next())
        reload.continuation.yield(Update(snapshot: nil, phase: .refreshing, revision: 16))
        await waitForProgress(in: coordinator)
        refreshing.cancel()
        await refreshing.value
        for await _ in reload.termination {}
        #expect(coordinator.update == nil)

        let changed = snapshot(owner: "wallet-a", revision: 3)
        observation.continuation.yield(Update(snapshot: changed, phase: .ready, revision: 17))
        await waitForSnapshot(changed, in: coordinator)
        viewing.cancel()
        await viewing.value
    }

    /// Verifies repeated gestures share work and cancellation preserves observation's own progress.
    @Test
    func `Overlapping manual refreshes share one request`() async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        let cached = snapshot(owner: "wallet-a", revision: 1)
        observation.continuation.yield(Update(snapshot: cached, phase: .refreshing, revision: 18))
        await waitForProgress(in: coordinator)
        let first = Task { await coordinator.refresh() }
        defer { first.cancel() }
        let reload = try #require(await requests.next())
        let joined = AsyncStream<Void>.makeStream()
        let second = Task {
            // The main-actor refresh registers synchronously before suspending;
            // the test cannot resume until that registration has completed.
            joined.continuation.finish()
            await coordinator.refresh()
        }
        defer { second.cancel() }
        for await _ in joined.stream {}
        #expect(await service.calls.count == 2)
        first.cancel()
        await first.value
        await second.value
        for await _ in reload.termination {}
        #expect(coordinator.update?.isRefreshing == true)

        observation.continuation.yield(Update(snapshot: cached, phase: .ready, revision: 19))
        viewing.cancel()
        await viewing.value
        #expect(coordinator.update?.snapshot == cached)
        #expect(coordinator.update?.isRefreshing == false)
    }

    /// Verifies a disconnection preserves holdings and allows explicit reload without reconnecting.
    @Test
    func `Subscription failure preserves data and allows manual refresh`() async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        let cached = snapshot(owner: "wallet-a", revision: 1)
        let error = RPCError.http(statusCode: 429, retryAfter: "3")
        observation.continuation.yield(Update(snapshot: cached, phase: .failed(error), revision: 20))
        observation.continuation.finish()
        await waitForSnapshot(cached, in: coordinator)
        #expect(coordinator.update?.error as? RPCError == error)
        #expect(coordinator.error == .rateLimited)

        let refreshing = Task { await coordinator.refresh() }
        defer { refreshing.cancel() }
        let reload = try #require(await requests.next())
        #expect(reload.kind == .refresh(.reload))
        reload.continuation.yield(Update(snapshot: cached, phase: .ready, revision: 21))
        reload.continuation.finish()
        await refreshing.value
        #expect(coordinator.update?.error == nil)
        #expect(coordinator.error == nil)
        #expect(await service.calls.count == 2)
        viewing.cancel()
        await viewing.value
    }

    /// Verifies independently queued streams cannot replace newer holdings with an older snapshot.
    @Test
    func `Late refresh errors retain the newest observed holdings`() async throws {
        let service = PortfolioResponses()
        let coordinator = PortfolioCoordinator(service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await coordinator.observe(for: "wallet-a", isActive: true) }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        let refreshing = Task { await coordinator.refresh() }
        defer { refreshing.cancel() }
        let reload = try #require(await requests.next())
        let recent = snapshot(owner: "wallet-a", revision: 3)
        observation.continuation.yield(Update(snapshot: recent, phase: .ready, revision: 22))
        await waitForSnapshot(recent, in: coordinator)
        let error = RPCError.http(statusCode: 429, retryAfter: nil)
        reload.continuation.yield(Update(snapshot: snapshot(owner: "wallet-a", revision: 1), phase: .failed(error), revision: 23, snapshotRevision: 0))
        reload.continuation.finish()
        await refreshing.value
        #expect(coordinator.update?.snapshot == recent)
        #expect(coordinator.update?.error as? RPCError == error)
        viewing.cancel()
        await viewing.value
    }

    /// Creates distinct complete results without wallet recovery or live addresses.
    /// - Parameters:
    ///   - owner: The test wallet's label.
    ///   - revision: A deterministic retrieval time.
    /// - Returns: A valid empty fungible portfolio.
    private func snapshot(owner: String, revision: TimeInterval) -> Snapshot {
        Snapshot(owner: owner, network: .devnet, holdings: [], fetchedAt: Date(timeIntervalSince1970: revision))
    }

    /// Creates a portfolio service that keeps its token lists and snapshots in a test's directory.
    /// - Parameter directory: The test's private directory.
    /// - Returns: A mainnet service that makes no requests for token-list edits.
    private func filePortfolio(in directory: URL) -> Portfolio {
        Portfolio(rpc: Solana(network: .mainnet), store: FileSnapshotStore(directory: directory),
                  tokenLists: FileTokenListStore(directory: directory.appendingPathComponent("TokenLists")))
    }

    /// Creates a priced portfolio whose provider order differs from its display order.
    /// - Parameter values: Each token's mint and USD value, in the provider's order; native SOL comes last.
    /// - Returns: A complete snapshot for `wallet-a`.
    private func pricedSnapshot(_ values: KeyValuePairs<String, Decimal>) -> Snapshot {
        let tokens = values.map { mint, total in
            Holding(id: .asset(mint), amount: Amount(units: 1, decimals: 0), name: nil, symbol: nil, imageURL: nil,
                    valuation: Valuation(pricePerUnit: total, total: total, currency: "USD"))
        }
        let solana = Holding(id: .nativeSOL, amount: Amount(units: 0, decimals: 9), name: "Solana", symbol: "SOL",
                             imageURL: nil, valuation: nil)
        return Snapshot(owner: "wallet-a", network: .devnet, holdings: tokens + [solana],
                        fetchedAt: Date(timeIntervalSince1970: 1))
    }

    /// Awaits observable snapshot publication without sleeps or polling.
    /// - Parameters:
    ///   - expected: The snapshot that must reach presentation state.
    ///   - coordinator: The presentation under test.
    private func waitForSnapshot(_ expected: Snapshot, in coordinator: PortfolioCoordinator) async {
        for await snapshot in Observations({ coordinator.update?.snapshot }) {
            if snapshot == expected { return }
        }
    }

    /// Awaits observable progress before exercising cancellation.
    /// - Parameter coordinator: The presentation under test.
    private func waitForProgress(in coordinator: PortfolioCoordinator) async {
        for await refreshing in Observations({ coordinator.update?.isRefreshing == true }) {
            if refreshing { return }
        }
    }
}
