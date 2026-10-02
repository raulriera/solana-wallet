import Foundation
import RPC
import Testing
@testable import Portfolio

/// Verifies cache age, explicit reloads, and separate price freshness through real provider adapters.
struct FreshnessTests {
    /// Verifies fresh data produces one ready state without any DAS or price traffic.
    /// - Parameter pricesOnly: Whether old holdings should be ignored by a price-only read.
    @Test(arguments: [false, true])
    func `Fresh cache completes without network requests`(pricesOnly: Bool) async throws {
        let fixture = FreshnessFixture()
        defer { fixture.removeFiles() }
        let cached = fixture.snapshot(holdingsAge: pricesOnly ? 600 : 299, pricesAge: 299)
        try fixture.store.save(cached, for: fixture.key)
        let das = AssetResponses { _ in throw URLError(.notConnectedToInternet) }
        let prices = PriceResponses { _ in throw URLError(.notConnectedToInternet) }
        let service: any PortfolioProviding = Portfolio(rpc: das.client, store: fixture.store,
                                                        prices: prices.client, now: { fixture.now })
        let stream = await (pricesOnly ? service.priceUpdates(for: "wallet") : service.updates(for: "wallet"))
        var updates = stream.makeAsyncIterator()
        let ready = try #require(await updates.next())
        #expect(ready.snapshot == cached)
        #expect(!ready.isRefreshing)
        #expect(ready.error == nil)
        #expect(await updates.next() == nil)
        #expect(await das.requests.isEmpty)
        #expect(await das.assetRequests.isEmpty)
        #expect(await prices.requests.isEmpty)
    }

    /// Verifies a portfolio without an independent price source only uses holdings freshness.
    @Test
    func `Fresh DAS-only portfolios do not require an independent price timestamp`() async throws {
        let fixture = FreshnessFixture()
        defer { fixture.removeFiles() }
        let cached = fixture.snapshot(holdingsAge: 1, pricesAge: nil)
        try fixture.store.save(cached, for: fixture.key)
        let das = AssetResponses { _ in throw URLError(.notConnectedToInternet) }
        let service = Portfolio(rpc: das.client, store: fixture.store, now: { fixture.now })
        var updates = await service.updates(for: "wallet").makeAsyncIterator()
        #expect(try #require(await updates.next()).snapshot == cached)
        #expect(await updates.next() == nil)
        #expect(await das.requests.isEmpty)
    }

    /// Verifies expiration is inclusive and a clock moving backward cannot make cache fresh indefinitely.
    /// - Parameter age: The holdings age in seconds, including a future timestamp.
    @Test(arguments: [300.0, 301.0, -1.0])
    func `Expired or future holdings are refreshed even when prices were just checked`(age: TimeInterval) async throws {
        let fixture = FreshnessFixture()
        defer { fixture.removeFiles() }
        try fixture.store.save(fixture.snapshot(holdingsAge: age, pricesAge: 0), for: fixture.key)
        let das = AssetResponses { request in emptyPage(request.page) }
        let prices = PriceResponses { _ in Data("{}".utf8) }
        let service = Portfolio(rpc: das.client, store: fixture.store, prices: prices.client, now: { fixture.now })
        var updates = await service.updates(for: "wallet").makeAsyncIterator()
        #expect(try #require(await updates.next()).isRefreshing)
        let ready = try #require(await updates.next())
        #expect(ready.error == nil)
        #expect(ready.holdings.first?.amount?.units == 200)
        #expect(await das.requests.count == 1)
        #expect(await prices.requests.count == 1)
    }

    /// Verifies a successful lookup with no quotes is cached across service recreation.
    /// - Parameter priceAge: An expired, future, or absent independent price timestamp.
    @Test(arguments: [nil, 300.0, -1.0])
    func `Stale prices refresh without DAS and unavailable quotes are still cached`(priceAge: TimeInterval?) async throws {
        let fixture = FreshnessFixture()
        defer { fixture.removeFiles() }
        let cached = fixture.snapshot(holdingsAge: 10, pricesAge: priceAge)
        try fixture.store.save(cached, for: fixture.key)
        let das = AssetResponses { _ in throw URLError(.notConnectedToInternet) }
        let prices = PriceResponses { _ in Data("{}".utf8) }
        let source = prices.client
        let service = Portfolio(rpc: das.client, store: fixture.store, prices: source, now: { fixture.now })
        var updates = await service.updates(for: "wallet").makeAsyncIterator()
        #expect(try #require(await updates.next()).snapshot == cached)
        let ready = try #require(await updates.next())
        #expect(ready.error == nil)
        let snapshot = try #require(ready.snapshot)
        #expect(snapshot.fetchedAt == cached.fetchedAt)
        #expect(snapshot.pricesFetchedAt == fixture.now)
        #expect(snapshot.holdings.first?.valuation == nil)
        #expect(fixture.store.snapshot(for: fixture.key) == snapshot)

        let recreated = Portfolio(rpc: das.client, store: fixture.store, prices: source, now: { fixture.now })
        var reused = await recreated.updates(for: "wallet").makeAsyncIterator()
        #expect(try #require(await reused.next()).snapshot == snapshot)
        #expect(await reused.next() == nil)
        #expect(await das.requests.isEmpty)
        #expect(await das.assetRequests.isEmpty)
        #expect(await prices.requests.count == 1)
    }

    /// Verifies explicit user actions reload fresh data and concurrent reloads share one operation.
    /// - Parameter pricesOnly: Whether to reload only prices or the whole portfolio.
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func `Explicit reload bypasses fresh cache and shares concurrent requests`(pricesOnly: Bool) async throws {
        let fixture = FreshnessFixture()
        defer { fixture.removeFiles() }
        let cached = fixture.snapshot(holdingsAge: 0, pricesAge: 0)
        try fixture.store.save(cached, for: fixture.key)
        let (pending, release) = AsyncStream<Void>.makeStream()
        defer { release.finish() }
        let das = AssetResponses { request in emptyPage(request.page) }
        let prices = PriceResponses { _ in
            for await _ in pending {}
            return Data("{}".utf8)
        }
        let service: any PortfolioProviding = Portfolio(rpc: das.client, store: fixture.store,
                                                        prices: prices.client, now: { fixture.now })
        let firstStream = await (pricesOnly ? service.priceUpdates(for: "wallet", policy: .reload)
                                           : service.updates(for: "wallet", policy: .reload))
        var first = firstStream.makeAsyncIterator()
        #expect(try #require(await first.next()).isRefreshing)
        let secondStream = await (pricesOnly ? service.priceUpdates(for: "wallet", policy: .reload)
                                            : service.updates(for: "wallet", policy: .reload))
        var second = secondStream.makeAsyncIterator()
        #expect(try #require(await second.next()).snapshot == cached)
        release.finish()
        let firstResult = try #require(await first.next())
        let secondResult = try #require(await second.next())
        #expect(firstResult.error == nil)
        #expect(firstResult.snapshot == secondResult.snapshot)
        #expect(firstResult.revision == secondResult.revision)
        #expect(firstResult.snapshotRevision == secondResult.snapshotRevision)
        #expect(firstResult.snapshot?.pricesFetchedAt == fixture.now)
        #expect(await das.requests.count == (pricesOnly ? 0 : 1))
        #expect(await prices.requests.count == 1)
        #expect(await first.next() == nil)
        #expect(await second.next() == nil)
    }

    /// Verifies older persisted snapshots remain readable and require an initial price lookup.
    @Test
    func `Snapshots without price freshness remain compatible`() throws {
        let fixture = FreshnessFixture()
        let original = fixture.snapshot(holdingsAge: 5, pricesAge: nil)
        let encoded = try JSONEncoder().encode(original)
        let fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(fields["pricesFetchedAt"] == nil)
        let decoded = try JSONDecoder().decode(Snapshot.self, from: encoded)
        #expect(decoded == original)
        #expect(decoded.pricesFetchedAt == nil)
    }
}

/// A private disk cache and fixed wall clock for one freshness test.
private struct FreshnessFixture: Sendable {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let key = CacheKey(owner: "wallet", network: .mainnet)
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    var store: FileSnapshotStore { FileSnapshotStore(directory: directory) }

    /// Creates holdings with independently controlled cache ages.
    /// - Parameters:
    ///   - holdingsAge: Seconds elapsed since balances were retrieved.
    ///   - pricesAge: Seconds elapsed since prices were checked, or `nil` if never checked.
    /// - Returns: A complete native SOL holding for freshness and reload tests.
    func snapshot(holdingsAge: TimeInterval, pricesAge: TimeInterval?) -> Snapshot {
        Snapshot(owner: "wallet", network: .mainnet, holdings: [
            Holding(id: .nativeSOL, amount: Amount(units: 100, decimals: 9), name: "Solana", symbol: "SOL",
                    imageURL: nil, valuation: Valuation(pricePerUnit: 1, total: 1, currency: "USD")),
        ], fetchedAt: now.addingTimeInterval(-holdingsAge), lastIndexedSlot: 123,
           pricesFetchedAt: pricesAge.map { now.addingTimeInterval(-$0) })
    }

    /// Removes only this test's persisted snapshots.
    func removeFiles() { try? FileManager.default.removeItem(at: directory) }
}

/// Produces a complete native-only DAS page with a changed balance.
/// - Parameter page: The requested page number.
/// - Returns: A valid empty fungible result and its native balance.
private func emptyPage(_ page: Int) -> Data {
    Data(#"{"page":\#(page),"limit":1000,"items":[],"nativeBalance":{"lamports":200}}"#.utf8)
}
