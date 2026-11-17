import Foundation
import Observation
import RPC
import Testing
import Transactions
@testable import Portfolio
@testable import widgets

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WalletPortfolioTests {
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

    @Test
    func `A wallet that nothing observes isn't read`() async {
        let service = PortfolioResponses()
        let portfolio = WalletPortfolio(owner: "wallet-a", service: service)

        await portfolio.refresh()

        #expect(portfolio.update == nil)
        #expect(await service.calls.isEmpty)
    }

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
        #expect(portfolio.holdings.map(\.asset.displaySymbol) == ["high", "low", "SOL"])

        let second = pricedSnapshot(["low": 9, "high": 5])
        observation.continuation.yield(Update(snapshot: second, phase: .ready, revision: 2))
        await waitForSnapshot(second, in: portfolio)
        #expect(portfolio.holdings.map(\.asset.displaySymbol) == ["low", "high", "SOL"])
        viewing.cancel()
        await viewing.value
    }

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

    private func pricedSnapshot(_ values: KeyValuePairs<String, Decimal>) -> Snapshot {
        let tokens = values.map { symbol, total in
            Holding.fixture(.fixture(symbol: symbol), amount: 1,
                            valuation: Valuation(pricePerUnit: total, total: total, currency: "USD"))
        }
        let solana = Holding(asset: .nativeSOL, balance: TokenAmount(lamports: 0),
                             imageURL: nil, valuation: nil)
        return Snapshot(owner: "wallet-a", network: .devnet, holdings: tokens + [solana])
    }

    private func waitForSnapshot(_ expected: Snapshot, in portfolio: WalletPortfolio) async {
        for await snapshot in Observations({ portfolio.update?.snapshot }) where snapshot == expected { return }
    }
}
