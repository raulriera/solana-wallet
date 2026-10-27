import Foundation
import Observation
import RPC
import Testing
@testable import Portfolio
@testable import widgets

/// Checks one wallet's shared portfolio: its single observation, its refreshes, and what it keeps when observers leave.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WalletPortfolioTests {
    /// Observers share one observation and its updates, and the last observer's end ends it.
    /// - Throws: A test prerequisite error.
    @Test
    func `Observers share one observation, which the last one ends`() async throws {
        let service = PortfolioResponses()
        let portfolio = WalletPortfolio(owner: "wallet-a", service: service)
        var requests = service.requests.makeAsyncIterator()
        let first = Task { await portfolio.observe() }
        let second = Task { await portfolio.observe() }
        defer {
            first.cancel()
            second.cancel()
        }
        let observation = try #require(await requests.next())

        first.cancel()
        await first.value
        let shared = Snapshot.fixture(owner: "wallet-a", lamports: 1)
        observation.continuation.yield(Update(snapshot: shared, phase: .ready, revision: 1))
        await waitForSnapshot(shared, in: portfolio)
        second.cancel()
        await second.value

        for await _ in observation.termination {}
        #expect(await service.calls.count == 1)
    }

    /// The last observer's end settles the progress it leaves and keeps the holdings for the next observer.
    /// - Throws: A test prerequisite error.
    @Test
    func `The last observer's end keeps the holdings and settles progress`() async throws {
        let service = PortfolioResponses()
        let portfolio = WalletPortfolio(owner: "wallet-a", service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await portfolio.observe() }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        let cached = Snapshot.fixture(owner: "wallet-a", lamports: 1)
        observation.continuation.yield(Update(snapshot: cached, phase: .ready, revision: 1))
        observation.continuation.yield(Update(snapshot: cached, phase: .refreshing, revision: 2))
        for await refreshing in Observations({ portfolio.update?.isRefreshing == true }) where refreshing { break }

        viewing.cancel()
        await viewing.value

        #expect(portfolio.update?.snapshot == cached)
        #expect(portfolio.update?.isRefreshing == false)
        #expect(portfolio.holdings.map(\.id) == [.nativeSOL])
    }

    /// A refresh reloads the observed wallet and returns once the reload ends.
    /// - Throws: A test prerequisite error.
    @Test
    func `A refresh reloads the observed wallet`() async throws {
        let service = PortfolioResponses()
        let portfolio = WalletPortfolio(owner: "wallet-a", service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await portfolio.observe() }
        defer { viewing.cancel() }
        _ = try #require(await requests.next())

        let refreshing = Task { await portfolio.refresh() }
        let reload = try #require(await requests.next())
        reload.continuation.finish()
        await refreshing.value

        #expect(reload.kind == .reload)
        #expect(reload.owner == "wallet-a")
        viewing.cancel()
        await viewing.value
    }

    /// A wallet that nothing observes isn't read, so an inactive window starts no work.
    @Test
    func `A wallet that nothing observes isn't read`() async {
        let service = PortfolioResponses()
        let portfolio = WalletPortfolio(owner: "wallet-a", service: service)

        await portfolio.refresh()

        #expect(portfolio.update == nil)
        #expect(await service.calls.isEmpty)
    }

    /// Holdings follow each new snapshot in display order.
    /// - Throws: A test prerequisite error.
    @Test
    func `Holdings follow each snapshot in display order`() async throws {
        let service = PortfolioResponses()
        let portfolio = WalletPortfolio(owner: "wallet-a", service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await portfolio.observe() }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        let first = pricedSnapshot(["low": 1, "high": 5])
        observation.continuation.yield(Update(snapshot: first, phase: .ready, revision: 1))
        await waitForSnapshot(first, in: portfolio)
        #expect(portfolio.holdings.map(\.id) == [.asset("high"), .asset("low"), .nativeSOL])

        let second = pricedSnapshot(["low": 9, "high": 5])
        observation.continuation.yield(Update(snapshot: second, phase: .ready, revision: 2))
        await waitForSnapshot(second, in: portfolio)
        #expect(portfolio.holdings.map(\.id) == [.asset("low"), .asset("high"), .nativeSOL])
        viewing.cancel()
        await viewing.value
    }

    /// What views read follows each update: the presentation, the classified failure, and the snapshot's order.
    /// - Throws: A test prerequisite error.
    @Test
    func `What views read follows each update`() async throws {
        let service = PortfolioResponses()
        let portfolio = WalletPortfolio(owner: "wallet-a", service: service)
        var requests = service.requests.makeAsyncIterator()
        let viewing = Task { await portfolio.observe() }
        defer { viewing.cancel() }
        let observation = try #require(await requests.next())
        #expect(portfolio.presentation == .blank)

        let cached = Snapshot.fixture(owner: "wallet-a", lamports: 1)
        observation.continuation.yield(Update(snapshot: cached, phase: .ready, revision: 1, snapshotRevision: 1))
        await waitForSnapshot(cached, in: portfolio)
        #expect(portfolio.presentation == .holdings)
        #expect(portfolio.error == nil)
        #expect(portfolio.snapshotRevision == 1)

        let limited = RPCError.http(statusCode: 429, retryAfter: nil)
        observation.continuation.yield(Update(snapshot: cached, phase: .failed(limited), revision: 2,
                                              snapshotRevision: 1))
        for await error in Observations({ portfolio.error }) where error != nil { break }
        #expect(portfolio.error == .rateLimited)
        #expect(portfolio.presentation == .holdings)
        #expect(portfolio.snapshotRevision == 1)
        viewing.cancel()
        await viewing.value
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
        return Snapshot(owner: "wallet-a", network: .devnet, holdings: tokens + [solana])
    }

    /// Awaits a snapshot without sleeps or polling.
    /// - Parameters:
    ///   - expected: The snapshot that must reach the portfolio.
    ///   - portfolio: The portfolio under test.
    private func waitForSnapshot(_ expected: Snapshot, in portfolio: WalletPortfolio) async {
        for await snapshot in Observations({ portfolio.update?.snapshot }) where snapshot == expected { return }
    }
}
