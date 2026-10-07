import Foundation
import RPC
import Testing
@testable import Portfolio

/// Verifies independent valuation, persistence, and coordination through real provider adapters.
struct PriceRefreshTests {
    /// Verifies price-only refreshes preserve balances and names, share SOL's quote, and clear omitted prices.
    /// - Throws: A fixture, refresh, or test prerequisite error.
    @Test
    func `Price-only refresh preserves holdings and never reads balances`() async throws {
        let fixture = PricingFixture()
        defer { fixture.removeFiles() }
        let cached = pricingSnapshot()
        try fixture.store.save(cached, for: fixture.key)
        let accounts = AccountResponses { _ in throw URLError(.notConnectedToInternet) }
        let prices = PriceResponses { _ in
            Data(#"{"\#(nativeMint)":{"usdPrice":100},"mint":{"usdPrice":0.1},"missing":{"createdAt":"2025-01-01T00:00:00Z","decimals":6}}"#.utf8)
        }
        let service: any PortfolioProviding = fixture.portfolio(rpc: accounts.client, prices: prices.client)
        var updates = await service.priceUpdates(for: testWallet).makeAsyncIterator()
        #expect(try #require(await updates.next()).snapshot == cached)
        let update = try #require(await updates.next())
        if let error = update.error { throw error }
        let refreshed = try #require(update.snapshot)

        #expect(refreshed.fetchedAt == cached.fetchedAt)
        #expect(refreshed.holdings.map(\.id) == cached.holdings.map(\.id))
        #expect(refreshed.holdings.map(\.amount) == cached.holdings.map(\.amount))
        #expect(refreshed.holdings.map(\.name) == cached.holdings.map(\.name))
        #expect(refreshed.holdings.map(\.imageURL) == cached.holdings.map(\.imageURL))
        #expect(refreshed.holdings.map(\.valuation?.total) == [100, 200, Decimal(string: "0.125"), nil])
        #expect(refreshed.holdings.prefix(3).allSatisfy { $0.valuation?.fetchedAt != nil && $0.valuation?.currency == "USD" })
        #expect(refreshed.holdings.last?.valuation == nil)
        #expect(await prices.requests == [[nativeMint, "mint", "missing"]])
        #expect(await accounts.requests.isEmpty)
        #expect(fixture.store.snapshot(for: fixture.key) == refreshed)
        #expect(await updates.next() == nil)
    }

    /// Verifies a full refresh values newly read amounts with the selected independent provider.
    /// - Throws: A fixture, refresh, or test prerequisite error.
    @Test
    func `Full portfolio refresh applies independent quotes to the new holdings`() async throws {
        let fixture = PricingFixture()
        defer { fixture.removeFiles() }
        let accounts = AccountResponses { _ in freshLedger }
        let prices = PriceResponses { _ in Data(#"{"\#(nativeMint)":{"usdPrice":100},"\#(usdcMint)":{"usdPrice":4}}"#.utf8) }
        let service = fixture.portfolio(rpc: accounts.client, prices: prices.client)
        var updates = await service.updates(for: testWallet).makeAsyncIterator()
        _ = try #require(await updates.next())
        let update = try #require(await updates.next())
        if let error = update.error { throw error }
        let snapshot = try #require(update.snapshot)
        #expect(snapshot.holdings.map(\.valuation?.total) == [100, 12, nil])
        #expect(snapshot.holdings.prefix(2).allSatisfy { $0.valuation?.fetchedAt != nil })
        #expect(await prices.requests == [[nativeMint, usdcMint, usdtMint]])
        #expect(await accounts.requests.count == 1)
        #expect(fixture.store.snapshot(for: fixture.key) == snapshot)
    }

    /// Verifies a failed quote request preserves the preceding complete snapshot without retrying.
    /// - Parameter fullRefresh: Whether the failure follows a fresh balance read.
    /// - Throws: A fixture or test prerequisite error.
    @Test(arguments: [false, true])
    func `Price failures preserve the cached snapshot without retrying`(fullRefresh: Bool) async throws {
        let fixture = PricingFixture()
        defer { fixture.removeFiles() }
        let cached = pricingSnapshot()
        try fixture.store.save(cached, for: fixture.key)
        let accounts = AccountResponses { _ in freshLedger }
        let prices = PriceResponses(status: 429) { _ in Data("{}".utf8) }
        let service = fixture.portfolio(rpc: accounts.client, prices: prices.client)
        let stream = await (fullRefresh ? service.updates(for: testWallet) : service.priceUpdates(for: testWallet))
        var updates = stream.makeAsyncIterator()
        _ = try #require(await updates.next())
        let failed = try #require(await updates.next())
        #expect(failed.error as? RPCError == .http(statusCode: 429, retryAfter: "2"))
        #expect(failed.snapshot == cached)
        #expect(fixture.store.snapshot(for: fixture.key) == cached)
        #expect(await prices.requests.count == 1)
        #expect(await accounts.requests.count == (fullRefresh ? 1 : 0))
    }

    /// Verifies absent prerequisites and network mismatches fail before any provider request.
    /// - Parameters:
    ///   - failure: The missing or incompatible price-refresh prerequisite.
    ///   - fullRefresh: Whether to verify a full refresh's network validation.
    /// - Throws: A fixture or test prerequisite error.
    @Test(arguments: [
        (PriceError.providerUnavailable, false), (.holdingsUnavailable, false), (.networkMismatch, false), (.networkMismatch, true),
    ])
    func `Price refresh rejects unavailable prerequisites before networking`(failure: PriceError, fullRefresh: Bool) async throws {
        let fixture = PricingFixture()
        defer { fixture.removeFiles() }
        if failure != .holdingsUnavailable { try fixture.store.save(pricingSnapshot(), for: fixture.key) }
        let accounts = AccountResponses(network: failure == .networkMismatch ? .devnet : .mainnet) { _ in freshLedger }
        let prices = PriceResponses { _ in Data("{}".utf8) }
        let service = fixture.portfolio(rpc: accounts.client, prices: failure == .providerUnavailable ? nil : prices.client)
        let stream = await (fullRefresh ? service.updates(for: testWallet) : service.priceUpdates(for: testWallet))
        var updates = stream.makeAsyncIterator()
        _ = try #require(await updates.next())
        let failed = try #require(await updates.next())
        #expect(failed.error as? PriceError == failure)
        #expect(await accounts.requests.isEmpty)
        #expect(await prices.requests.isEmpty)
    }

    /// Verifies a full refresh supersedes pending prices without allowing stale balances to overwrite new holdings.
    /// - Parameter pricesFirst: Whether a price refresh or full refresh starts first.
    /// - Throws: A fixture, refresh, or test prerequisite error.
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func `Overlapping full and price refreshes finish with the new holdings`(pricesFirst: Bool) async throws {
        let fixture = PricingFixture()
        defer { fixture.removeFiles() }
        try fixture.store.save(pricingSnapshot(), for: fixture.key)
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, announce) = AsyncStream<Void>.makeStream()
        defer { release.finish(); announce.finish() }
        let accounts = AccountResponses { _ in
            if !pricesFirst {
                announce.yield(())
                for await _ in pending {}
            }
            return freshLedger
        }
        let prices = PriceResponses { mints in
            if mints.contains("mint") {
                announce.yield(())
                for await _ in pending {}
            }
            return Data(#"{"\#(nativeMint)":{"usdPrice":100},"\#(usdcMint)":{"usdPrice":4}}"#.utf8)
        }
        let service = fixture.portfolio(rpc: accounts.client, prices: prices.client)
        let firstStream = await (pricesFirst ? service.priceUpdates(for: testWallet) : service.updates(for: testWallet))
        var first = firstStream.makeAsyncIterator()
        _ = try #require(await first.next())
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())
        let secondStream = await (pricesFirst ? service.updates(for: testWallet) : service.priceUpdates(for: testWallet))
        var second = secondStream.makeAsyncIterator()
        _ = try #require(await second.next())
        release.finish()
        let firstResult = try #require(await first.next())
        let secondResult = try #require(await second.next())
        #expect(firstResult.error == nil)
        #expect(secondResult.error == nil)
        #expect(firstResult.snapshot == secondResult.snapshot)
        #expect(firstResult.holdings.map(\.id) == [.nativeSOL, .asset(usdcMint), .asset(usdtMint)])
        #expect(firstResult.holdings[1].valuation?.total == 12)
        #expect(fixture.store.snapshot(for: fixture.key) == firstResult.snapshot)
        #expect(await accounts.requests.count == 1)
        #expect(await prices.requests.count == (pricesFirst ? 2 : 1))
        #expect(await first.next() == nil)
        #expect(await second.next() == nil)
    }

    /// Verifies removal cancels price work and cannot restore a deleted snapshot.
    /// - Throws: A fixture or test prerequisite error.
    @Test(.timeLimit(.minutes(1)))
    func `Removing a portfolio during price refresh prevents cache restoration`() async throws {
        let fixture = PricingFixture()
        defer { fixture.removeFiles() }
        try fixture.store.save(pricingSnapshot(), for: fixture.key)
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, announce) = AsyncStream<Void>.makeStream()
        let (cancelled, cancelledContinuation) = AsyncStream<Void>.makeStream()
        defer { release.finish(); announce.finish(); cancelledContinuation.finish() }
        let accounts = AccountResponses { _ in freshLedger }
        let prices = PriceResponses { _ in
            announce.yield(())
            for await _ in pending {}
            if Task.isCancelled { cancelledContinuation.yield(()) }
            return Data("{}".utf8)
        }
        let service = fixture.portfolio(rpc: accounts.client, prices: prices.client)
        var updates = await service.priceUpdates(for: testWallet).makeAsyncIterator()
        _ = try #require(await updates.next())
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())
        try await service.removeData(for: testWallet)
        var cancelledIterator = cancelled.makeAsyncIterator()
        _ = try #require(await cancelledIterator.next())
        #expect(await updates.next() == nil)
        #expect(fixture.store.snapshot(for: fixture.key) == nil)
        #expect(await accounts.requests.isEmpty)
    }
}

/// A disk cache isolated to one pricing test.
private struct PricingFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let key = CacheKey(owner: testWallet, network: .mainnet)
    var store: FileSnapshotStore { FileSnapshotStore(directory: directory) }

    /// Creates a service that keeps its snapshots in this test's directory.
    /// - Parameters:
    ///   - rpc: The client whose balance reads the service makes.
    ///   - prices: The independent price provider, or `nil` for none.
    /// - Returns: The service under test.
    func portfolio(rpc: any RPC, prices: (any PriceProviding)?) -> Portfolio {
        Portfolio(rpc: rpc, store: store, tokenLists: isolatedTokenLists(), prices: prices)
    }

    /// Removes only this fixture's cache files.
    func removeFiles() { try? FileManager.default.removeItem(at: directory) }
}

/// A new balance read: 1 SOL and 3 USDC, with no USDT account.
private let freshLedger = Ledger(lamports: 1_000_000_000, tokens: [usdcMint: 3_000_000])

/// Creates a snapshot whose identities, names, and retrieval time must survive repricing.
/// - Returns: SOL, Wrapped SOL, a fungible token, and a previously priced token with no new quote.
private func pricingSnapshot() -> Snapshot {
    let holdings = [
        Holding(id: .nativeSOL, amount: Amount(units: 1_000_000_000, decimals: 9), name: "Solana", symbol: "SOL",
                imageURL: nil, valuation: nil),
        Holding(id: .asset(nativeMint), amount: Amount(units: 2_000_000_000, decimals: 9), name: "Wrapped SOL",
                symbol: "WSOL", imageURL: nil, valuation: nil),
        Holding(id: .asset("mint"), amount: Amount(units: 1_250_000, decimals: 6), name: "Token", symbol: "TOK",
                imageURL: URL(string: "https://example.com/token.png"), valuation: nil),
        Holding(id: .asset("missing"), amount: Amount(units: 1, decimals: 0), name: nil, symbol: nil, imageURL: nil,
                valuation: Valuation(pricePerUnit: 20, total: 20, currency: "USDC", fetchedAt: .distantPast)),
    ]
    return Snapshot(owner: testWallet, network: .mainnet, holdings: holdings, fetchedAt: .distantPast)
}
