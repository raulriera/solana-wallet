import Foundation
import RPC
import Testing
@testable import Portfolio

/// Tests complete cache-and-refresh cycles with typed RPC fixtures and isolated disk stores.
struct PortfolioTests {
    /// Verifies immediate reuse, complete pagination, and persistence of a refreshed snapshot.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test("cached holdings arrive before a complete refreshed portfolio", .timeLimit(.minutes(1)))
    func cachedHoldingsArriveBeforeACompleteRefreshedPortfolio() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let cached = snapshot(owner: "wallet", network: .mainnet, units: 3)
        try fixture.store.save(cached, for: CacheKey(owner: "wallet", network: .mainnet))
        let (pending, release) = AsyncStream<Void>.makeStream()
        defer { release.finish() }
        let rpc = StubRPC { request in
            if request.page == 1 { for await _ in pending {} }
            return page(for: request, assets: request.page == 1 ? [asset(units: 9_007_199_254_740_993)] : [])
        }
        let service = Portfolio(rpc: rpc, store: fixture.store, pageSize: 1)
        var iterator = service.updates(for: "wallet").makeAsyncIterator()

        let initial = try #require(await iterator.next())
        #expect(initial.snapshot == cached)
        #expect(initial.isRefreshing)
        release.finish()
        let updated = try #require(await iterator.next())
        let result = try #require(updated.snapshot)

        #expect(result.holdings.first { $0.id == .asset("mint") }?.amount?.units == 9_007_199_254_740_993)
        #expect(result.holdings.first { $0.id == .nativeSOL }?.amount?.units == 100)
        #expect(result.lastIndexedSlot == 12345)
        #expect(result.unpricedHoldingCount == 2)
        #expect(result.knownValuesByCurrency.isEmpty)
        #expect(!updated.isRefreshing)
        #expect(updated.error == nil)
        #expect(fixture.store.snapshot(for: CacheKey(owner: "wallet", network: .mainnet)) == result)
        #expect(await iterator.next() == nil)
        let requests = await rpc.requests
        #expect(requests.map(\.page) == [1, 2])
        #expect(requests.map(\.includesNativeBalance) == [true, false])
    }

    /// Verifies that malformed image metadata doesn't stop holdings or later pages from reaching the portfolio.
    ///
    /// This integration fixture exercises RPC decoding before the portfolio
    /// consumes the response, reproducing the original failure across both modules.
    ///
    /// - Throws: A decoding error or failed test prerequisite.
    @Test("portfolio keeps holdings and later pages when an asset image is malformed")
    func portfolioKeepsHoldingsAndLaterPagesWhenAnAssetImageIsMalformed() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let rpc = StubRPC { request in
            if request.page == 1 {
                let data = Data(#"""
                    {"page":1,"limit":2,"items":[
                        {"id":"collectible","interface":"V1_NFT",
                         "content":{"metadata":{"name":"Example Collectible"},"links":{"image":false}},
                         "token_info":{"balance":1,"decimals":0}},
                        {"id":"first-mint","interface":"FungibleToken",
                         "token_info":{"balance":42,"decimals":6}}
                    ],"nativeBalance":{"lamports":100}}
                    """#.utf8)
                return try JSONDecoder().decode(GetAssetsByOwner.Response.self, from: data)
            }
            return page(for: request, assets: request.page == 2 ? [asset(units: 7)] : [])
        }
        let service = Portfolio(rpc: rpc, store: fixture.store, pageSize: 2)
        var iterator = service.updates(for: "wallet").makeAsyncIterator()
        _ = try #require(await iterator.next())

        let updated = try #require(await iterator.next())
        let result = try #require(updated.snapshot)

        #expect(updated.error == nil)
        #expect(!updated.isRefreshing)
        #expect(result.holdings.map(\.id) == [.nativeSOL, .asset("collectible"), .asset("first-mint"), .asset("mint")])
        #expect(result.holdings.map(\.amount) == [
            Amount(units: 100, decimals: 9), Amount(units: 1, decimals: 0),
            Amount(units: 42, decimals: 6), Amount(units: 7, decimals: 6),
        ])
        let collectible = try #require(result.holdings.first { $0.id == .asset("collectible") })
        #expect(collectible.name == "Example Collectible")
        #expect(collectible.imageURL == nil)
        #expect(await rpc.requests.map(\.page) == [1, 2, 3])
        #expect(fixture.store.snapshot(for: CacheKey(owner: "wallet", network: .mainnet)) == result)
        #expect(await iterator.next() == nil)
    }

    /// Verifies that an initial failure reports an error without inventing a zero portfolio.
    ///
    /// - Throws: A failed test prerequisite.
    @Test("an uncached offline wallet keeps an absent snapshot")
    func anUncachedOfflineWalletKeepsAnAbsentSnapshot() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let rpc = StubRPC { _ in throw RPCError.transport(.notConnectedToInternet) }
        let service = Portfolio(rpc: rpc, store: fixture.store)
        var iterator = service.updates(for: "wallet").makeAsyncIterator()

        let initial = try #require(await iterator.next())
        #expect(initial.snapshot == nil)
        #expect(initial.holdings.isEmpty)
        #expect(initial.isRefreshing)
        let failed = try #require(await iterator.next())
        #expect(failed.snapshot == nil)
        #expect(failed.error as? RPCError == .transport(.notConnectedToInternet))
        #expect(!failed.isRefreshing)
        #expect(await iterator.next() == nil)
    }

    /// Verifies that a later page failure never replaces a complete persisted portfolio.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test("a failed later page preserves the previous complete snapshot")
    func aFailedLaterPagePreservesThePreviousCompleteSnapshot() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let cached = snapshot(owner: "wallet", network: .mainnet, units: 3)
        let key = CacheKey(owner: "wallet", network: .mainnet)
        try fixture.store.save(cached, for: key)
        let rpc = StubRPC { request in
            if request.page == 2 { throw RPCError.transport(.notConnectedToInternet) }
            return page(for: request, assets: [asset(units: 100)])
        }
        let service = Portfolio(rpc: rpc, store: fixture.store, pageSize: 1)
        var iterator = service.updates(for: "wallet").makeAsyncIterator()
        _ = await iterator.next()

        let failed = try #require(await iterator.next())

        #expect(failed.snapshot == cached)
        #expect(failed.error as? RPCError == .transport(.notConnectedToInternet))
        #expect(fixture.store.snapshot(for: key) == cached)
    }

    /// Verifies that a successful empty token list removes previously held tokens.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test("a successful empty wallet replaces old token holdings")
    func aSuccessfulEmptyWalletReplacesOldTokenHoldings() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let key = CacheKey(owner: "wallet", network: .mainnet)
        try fixture.store.save(snapshot(owner: "wallet", network: .mainnet, units: 3), for: key)
        let rpc = StubRPC { request in
            GetAssetsByOwner.Response(lastIndexedSlot: 12345, page: request.page, limit: request.limit,
                                      items: [], nativeBalance: NativeBalance(lamports: 0, pricePerSOL: nil, totalPrice: nil))
        }
        let service = Portfolio(rpc: rpc, store: fixture.store)
        var iterator = service.updates(for: "wallet").makeAsyncIterator()
        _ = await iterator.next()

        let updated = try #require(await iterator.next())

        #expect(updated.holdings.map(\.id) == [.nativeSOL])
        #expect(updated.holdings.first?.amount == Amount(units: 0, decimals: 9))
        #expect(updated.error == nil)
        #expect(fixture.store.snapshot(for: key) == updated.snapshot)
    }

    /// Verifies that repeating a populated page fails instead of fetching indefinitely.
    ///
    /// - Throws: A failed test prerequisite.
    @Test("repeated asset pages stop the refresh without saving partial holdings")
    func repeatedAssetPagesStopTheRefreshWithoutSavingPartialHoldings() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let rpc = StubRPC { request in page(for: request, assets: [asset(units: 1)]) }
        let service = Portfolio(rpc: rpc, store: fixture.store, pageSize: 1)
        var iterator = service.updates(for: "wallet").makeAsyncIterator()
        _ = await iterator.next()

        let failed = try #require(await iterator.next())

        #expect(failed.error is FetchError)
        #expect(failed.snapshot == nil)
        #expect(await rpc.requests.count == 2)
        #expect(fixture.store.snapshot(for: CacheKey(owner: "wallet", network: .mainnet)) == nil)
    }

    /// Verifies that forgetting a wallet clears persisted data and cancels its active request.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test("removing wallet data clears its snapshot and stops its refresh", .timeLimit(.minutes(1)))
    func removingWalletDataClearsItsSnapshotAndStopsItsRefresh() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let key = CacheKey(owner: "wallet", network: .mainnet)
        try fixture.store.save(snapshot(owner: "wallet", network: .mainnet, units: 3), for: key)
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (cancelled, cancelledContinuation) = AsyncStream<Void>.makeStream()
        defer { release.finish(); startedContinuation.finish(); cancelledContinuation.finish() }
        let rpc = StubRPC { request in
            startedContinuation.yield(())
            for await _ in pending {}
            if Task.isCancelled { cancelledContinuation.yield(()) }
            return page(for: request, assets: [asset(units: 100)])
        }
        let service = Portfolio(rpc: rpc, store: fixture.store)
        var iterator = service.updates(for: "wallet").makeAsyncIterator()
        _ = try #require(await iterator.next())
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())

        try await service.removeData(for: "wallet")

        #expect(await iterator.next() == nil)
        var cancelledIterator = cancelled.makeAsyncIterator()
        _ = try #require(await cancelledIterator.next())
        #expect(fixture.store.snapshot(for: key) == nil)
        try await service.removeData(for: "wallet")
    }

    /// Verifies disk reuse by a new service while keeping wallet and network identities separate.
    ///
    /// - Parameters:
    ///   - network: The network of the recreated service.
    ///   - owner: The requested wallet.
    ///   - expectedUnits: The amount belonging only to this wallet and network.
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test("persisted snapshots stay isolated by wallet and network", arguments: [
        (Network.mainnet, "wallet-a", UInt64(11)),
        (.devnet, "wallet-a", UInt64(22)),
        (.mainnet, "wallet-b", UInt64(33)),
    ])
    func persistedSnapshotsStayIsolatedByWalletAndNetwork(network: Network, owner: String, expectedUnits: UInt64) async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        for (savedNetwork, savedOwner, units) in [(Network.mainnet, "wallet-a", UInt64(11)), (.devnet, "wallet-a", 22), (.mainnet, "wallet-b", 33)] {
            try fixture.store.save(snapshot(owner: savedOwner, network: savedNetwork, units: units),
                                   for: CacheKey(owner: savedOwner, network: savedNetwork))
        }
        let rpc = StubRPC(network: network) { _ in throw RPCError.transport(.notConnectedToInternet) }
        let recreatedStore = FileSnapshotStore(directory: fixture.directory)
        let service = Portfolio(rpc: rpc, store: recreatedStore)
        var iterator = service.updates(for: owner).makeAsyncIterator()

        let initial = try #require(await iterator.next())
        let failed = try #require(await iterator.next())

        #expect(initial.snapshot?.owner == owner)
        #expect(initial.snapshot?.network == network)
        #expect(initial.holdings.first?.amount?.units == expectedUnits)
        #expect(failed.snapshot == initial.snapshot)
    }

    /// Verifies that cancelling one consumer leaves another consumer's shared refresh running.
    ///
    /// - Throws: A failed test prerequisite.
    @Test("concurrent consumers share a refresh when one cancels", .timeLimit(.minutes(1)))
    func concurrentConsumersShareARefreshWhenOneCancels() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (observed, observedContinuation) = AsyncStream<Void>.makeStream()
        defer { release.finish(); startedContinuation.finish(); observedContinuation.finish() }
        let rpc = StubRPC { request in
            if request.page == 1 {
                startedContinuation.yield(())
                for await _ in pending {}
                try Task.checkCancellation()
            }
            return page(for: request, assets: request.page == 1 ? [asset(units: 7)] : [])
        }
        let service = Portfolio(rpc: rpc, store: fixture.store)
        let first = Task {
            for await _ in service.updates(for: "wallet") { observedContinuation.yield(()) }
        }
        defer { first.cancel() }
        var observedIterator = observed.makeAsyncIterator()
        _ = try #require(await observedIterator.next())
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())
        var second = service.updates(for: "wallet").makeAsyncIterator()
        _ = try #require(await second.next())
        #expect(await rpc.requests.count == 1)

        first.cancel()
        await first.value
        release.finish()

        let updated = try #require(await second.next())
        #expect(updated.holdings.first { $0.id == .asset("mint") }?.amount?.units == 7)
        #expect(updated.error == nil)
        #expect(await second.next() == nil)
        #expect(await rpc.requests.count == 2)
    }
}

/// A real disk store isolated to one test invocation.
private struct Fixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var store: FileSnapshotStore { FileSnapshotStore(directory: directory) }

    /// Removes only this test's temporary files.
    func removeFiles() { try? FileManager.default.removeItem(at: directory) }
}

/// An RPC test double that records requests and returns public typed fixtures.
private actor StubRPC: RPC {
    nonisolated let network: Network
    private(set) var requests: [GetAssetsByOwner] = []
    private let respond: @Sendable (GetAssetsByOwner) async throws -> GetAssetsByOwner.Response

    /// Creates an RPC double with a typed DAS response handler.
    ///
    /// - Parameters:
    ///   - network: The network associated with this double.
    ///   - respond: The handler that supplies each DAS page.
    init(network: Network = .mainnet, respond: @escaping @Sendable (GetAssetsByOwner) async throws -> GetAssetsByOwner.Response) {
        self.network = network
        self.respond = respond
    }

    /// Records a DAS request and returns its typed fixture.
    ///
    /// - Parameter request: The request sent by the portfolio service.
    /// - Returns: The fixture response.
    /// - Throws: A handler error or a failed prerequisite for an unexpected request type.
    func send<Request: RPCRequest>(_ request: Request) async throws -> Request.Response {
        let request = try #require(request as? GetAssetsByOwner)
        requests.append(request)
        return try #require(await respond(request) as? Request.Response)
    }
}

/// Creates an unpriced token fixture with an exact integer balance.
///
/// - Parameter units: The balance in the token's smallest units.
/// - Returns: A token with deliberately absent metadata and price information.
private func asset(units: UInt64) -> Asset {
    Asset(id: "mint", interface: "FungibleToken", name: nil, symbol: nil, imageURL: nil,
          balance: units, decimals: 6, price: nil)
}

/// Creates a page matching the request, including native SOL only when requested.
///
/// - Parameters:
///   - request: The request whose pagination settings to echo.
///   - assets: The assets supplied on this page.
/// - Returns: A typed DAS page.
private func page(for request: GetAssetsByOwner, assets: [Asset]) -> GetAssetsByOwner.Response {
    GetAssetsByOwner.Response(lastIndexedSlot: 12345, page: request.page, limit: request.limit, items: assets,
                              nativeBalance: request.includesNativeBalance ? NativeBalance(lamports: 100, pricePerSOL: nil, totalPrice: nil) : nil)
}

/// Creates a previously retrieved portfolio fixture.
///
/// - Parameters:
///   - owner: The wallet address.
///   - network: The snapshot's network.
///   - units: The cached token balance.
/// - Returns: An immutable snapshot with an earlier successful retrieval time.
private func snapshot(owner: String, network: Network, units: UInt64) -> Snapshot {
    Snapshot(owner: owner, network: network,
             holdings: [Holding(id: .asset("mint"), amount: Amount(units: units, decimals: 6),
                                name: nil, symbol: nil, imageURL: nil, valuation: nil)],
             fetchedAt: Date(timeIntervalSince1970: 1), lastIndexedSlot: 10)
}
