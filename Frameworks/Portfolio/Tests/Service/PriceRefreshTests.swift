import Foundation
import RPC
import Testing
@testable import Portfolio

/// Verifies independent valuation, persistence, and coordination through real provider adapters.
struct PriceRefreshTests {
    /// Verifies price-only refreshes preserve balances and metadata, share SOL's quote, and clear omitted prices.
    /// - Throws: A fixture, refresh, or test prerequisite error.
    @Test
    func `Price-only refresh preserves holdings and never queries DAS`() async throws {
        let fixture = PricingFixture()
        defer { fixture.removeFiles() }
        let cached = pricingSnapshot()
        try fixture.store.save(cached, for: fixture.key)
        let das = AssetResponses { _ in throw URLError(.notConnectedToInternet) }
        let prices = PriceResponses { _ in
            Data(#"{"So11111111111111111111111111111111111111112":{"usdPrice":100},"mint":{"usdPrice":0.1},"missing":{"createdAt":"2025-01-01T00:00:00Z","decimals":6}}"#.utf8)
        }
        let service: any PortfolioProviding = Portfolio(rpc: das.client, store: fixture.store, prices: prices.client)
        var updates = await service.priceUpdates(for: "wallet").makeAsyncIterator()
        #expect(try #require(await updates.next()).snapshot == cached)
        let update = try #require(await updates.next())
        if let error = update.error { throw error }
        let refreshed = try #require(update.snapshot)

        #expect(refreshed.fetchedAt == cached.fetchedAt)
        #expect(refreshed.lastIndexedSlot == cached.lastIndexedSlot)
        #expect(refreshed.holdings.map(\.id) == cached.holdings.map(\.id))
        #expect(refreshed.holdings.map(\.amount) == cached.holdings.map(\.amount))
        #expect(refreshed.holdings.map(\.metadata) == cached.holdings.map(\.metadata))
        #expect(refreshed.holdings.map(\.name) == cached.holdings.map(\.name))
        #expect(refreshed.holdings.map(\.imageURL) == cached.holdings.map(\.imageURL))
        #expect(refreshed.holdings.map(\.valuation?.total) == [100, 200, Decimal(string: "0.125"), nil])
        #expect(refreshed.holdings.prefix(3).allSatisfy { $0.valuation?.fetchedAt != nil && $0.valuation?.currency == "USD" })
        #expect(refreshed.holdings.last?.valuation == nil)
        #expect(await prices.requests == [[nativeMint, "mint", "missing"]])
        #expect(await das.requests.isEmpty)
        #expect(await das.assetRequests.isEmpty)
        #expect(fixture.store.snapshot(for: fixture.key) == refreshed)
        #expect(await updates.next() == nil)
    }

    /// Verifies a full refresh values newly fetched amounts with the selected independent provider.
    /// - Throws: A fixture, refresh, or test prerequisite error.
    @Test
    func `Full portfolio refresh applies independent quotes to the new holdings`() async throws {
        let fixture = PricingFixture()
        defer { fixture.removeFiles() }
        let das = AssetResponses { request in freshPage(request.page) }
        let prices = PriceResponses { _ in Data(#"{"So11111111111111111111111111111111111111112":{"usdPrice":100},"new-mint":{"usdPrice":4}}"#.utf8) }
        let service = Portfolio(rpc: das.client, store: fixture.store, prices: prices.client)
        var updates = await service.updates(for: "wallet").makeAsyncIterator()
        _ = try #require(await updates.next())
        let update = try #require(await updates.next())
        if let error = update.error { throw error }
        let snapshot = try #require(update.snapshot)
        #expect(snapshot.holdings.map(\.valuation?.total) == [100, 12])
        #expect(snapshot.holdings.last?.metadata?.description == "Preserved")
        #expect(snapshot.holdings.allSatisfy { $0.valuation?.fetchedAt != nil })
        #expect(await prices.requests == [[nativeMint, "new-mint"]])
        #expect(await das.requests.map(\.page) == [1, 2])
        #expect(fixture.store.snapshot(for: fixture.key) == snapshot)
    }

    /// Verifies a failed quote request preserves the preceding complete snapshot without retrying.
    /// - Parameter fullRefresh: Whether the failure follows a fresh holdings fetch.
    /// - Throws: A fixture or test prerequisite error.
    @Test(arguments: [false, true])
    func `Price failures preserve the cached snapshot without retrying`(fullRefresh: Bool) async throws {
        let fixture = PricingFixture()
        defer { fixture.removeFiles() }
        let cached = pricingSnapshot()
        try fixture.store.save(cached, for: fixture.key)
        let das = AssetResponses { request in freshPage(request.page) }
        let prices = PriceResponses(status: 429) { _ in Data("{}".utf8) }
        let service = Portfolio(rpc: das.client, store: fixture.store, prices: prices.client)
        let stream = await (fullRefresh ? service.updates(for: "wallet") : service.priceUpdates(for: "wallet"))
        var updates = stream.makeAsyncIterator()
        _ = try #require(await updates.next())
        let failed = try #require(await updates.next())
        #expect(failed.error as? RPCError == .http(statusCode: 429, retryAfter: "2"))
        #expect(failed.snapshot == cached)
        #expect(fixture.store.snapshot(for: fixture.key) == cached)
        #expect(await prices.requests.count == 1)
        #expect(await das.requests.count == (fullRefresh ? 2 : 0))
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
        let das = AssetResponses(network: failure == .networkMismatch ? .devnet : .mainnet) { request in freshPage(request.page) }
        let prices = PriceResponses { _ in Data("{}".utf8) }
        let service = Portfolio(rpc: das.client, store: fixture.store,
                                prices: failure == .providerUnavailable ? nil : prices.client)
        let stream = await (fullRefresh ? service.updates(for: "wallet") : service.priceUpdates(for: "wallet"))
        var updates = stream.makeAsyncIterator()
        _ = try #require(await updates.next())
        let failed = try #require(await updates.next())
        #expect(failed.error as? PriceError == failure)
        #expect(await das.requests.isEmpty)
        #expect(await das.assetRequests.isEmpty)
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
        let das = AssetResponses { request in
            if !pricesFirst && request.page == 1 {
                announce.yield(())
                for await _ in pending {}
            }
            return freshPage(request.page)
        }
        let prices = PriceResponses { mints in
            if mints.contains("mint") {
                announce.yield(())
                for await _ in pending {}
            }
            return Data(#"{"So11111111111111111111111111111111111111112":{"usdPrice":100},"new-mint":{"usdPrice":4}}"#.utf8)
        }
        let service = Portfolio(rpc: das.client, store: fixture.store, prices: prices.client)
        let firstStream = await (pricesFirst ? service.priceUpdates(for: "wallet") : service.updates(for: "wallet"))
        var first = firstStream.makeAsyncIterator()
        _ = try #require(await first.next())
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())
        let secondStream = await (pricesFirst ? service.updates(for: "wallet") : service.priceUpdates(for: "wallet"))
        var second = secondStream.makeAsyncIterator()
        _ = try #require(await second.next())
        release.finish()
        let firstResult = try #require(await first.next())
        let secondResult = try #require(await second.next())
        #expect(firstResult.error == nil)
        #expect(secondResult.error == nil)
        #expect(firstResult.snapshot == secondResult.snapshot)
        #expect(firstResult.holdings.map(\.id) == [.nativeSOL, .asset("new-mint")])
        #expect(firstResult.holdings.last?.valuation?.total == 12)
        #expect(fixture.store.snapshot(for: fixture.key) == firstResult.snapshot)
        #expect(await das.requests.map(\.page) == [1, 2])
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
        let das = AssetResponses { request in freshPage(request.page) }
        let prices = PriceResponses { _ in
            announce.yield(())
            for await _ in pending {}
            if Task.isCancelled { cancelledContinuation.yield(()) }
            return Data("{}".utf8)
        }
        let service = Portfolio(rpc: das.client, store: fixture.store, prices: prices.client)
        var updates = await service.priceUpdates(for: "wallet").makeAsyncIterator()
        _ = try #require(await updates.next())
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())
        try await service.removeData(for: "wallet")
        var cancelledIterator = cancelled.makeAsyncIterator()
        _ = try #require(await cancelledIterator.next())
        #expect(await updates.next() == nil)
        #expect(fixture.store.snapshot(for: fixture.key) == nil)
        #expect(await das.requests.isEmpty)
    }
}

/// A disk cache isolated to one pricing test.
private struct PricingFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let key = CacheKey(owner: "wallet", network: .mainnet)
    var store: FileSnapshotStore { FileSnapshotStore(directory: directory) }

    /// Removes only this fixture's cache files.
    func removeFiles() { try? FileManager.default.removeItem(at: directory) }
}

private let nativeMint = "So11111111111111111111111111111111111111112"

/// Creates a snapshot whose identities, metadata, and retrieval time must survive repricing.
/// - Returns: SOL, Wrapped SOL, a fungible token, and a previously priced token with no new quote.
private func pricingSnapshot() -> Snapshot {
    let holdings = [
        Holding(id: .nativeSOL, amount: Amount(units: 1_000_000_000, decimals: 9), name: "Solana", symbol: "SOL", imageURL: nil, valuation: nil),
        Holding(id: .asset(nativeMint), amount: Amount(units: 2_000_000_000, decimals: 9), name: "Wrapped SOL", symbol: "WSOL", imageURL: nil, valuation: nil),
        Holding(id: .asset("mint"), amount: Amount(units: 1_250_000, decimals: 6), name: "Token", symbol: "TOK",
                imageURL: URL(string: "https://example.com/token.png"), valuation: nil, metadata: Metadata(description: "Kept")),
        Holding(id: .asset("missing"), amount: Amount(units: 1, decimals: 0), name: nil, symbol: nil, imageURL: nil,
                valuation: Valuation(pricePerUnit: 20, total: 20, currency: "USDC", fetchedAt: .distantPast)),
    ]
    return Snapshot(owner: "wallet", network: .mainnet, holdings: holdings, fetchedAt: .distantPast, lastIndexedSlot: 123)
}

/// Creates complete DAS pages with deliberately different embedded prices from the price source.
/// - Parameter page: The requested page number.
/// - Returns: One fungible holding followed by an empty page.
private func freshPage(_ page: Int) -> Data {
    let items = page == 1 ? #"""
    [{"id":"new-mint","interface":"FungibleToken","content":{"metadata":{"description":"Preserved"}},
      "token_info":{"balance":3000000,"decimals":6,"price_info":{"price_per_token":999,"total_price":2997,"currency":"USDC"}}}]
    """# : "[]"
    return Data(#"{"page":\#(page),"limit":1000,"items":\#(items),"nativeBalance":{"lamports":1000000000,"price_per_sol":999,"total_price":999}}"#.utf8)
}
