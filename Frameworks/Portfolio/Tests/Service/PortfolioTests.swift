import Foundation
@testable import RPC
import Testing
@testable import Portfolio

/// Tests complete cache-and-refresh cycles with real RPC decoding, HTTP fixtures, and isolated disk stores.
struct PortfolioTests {
    /// Verifies immediate reuse, complete pagination, and persistence of a refreshed snapshot.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test(.timeLimit(.minutes(1)))
    func `Cached holdings arrive before a complete refreshed portfolio`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let cached = snapshot(owner: "wallet", network: .mainnet, units: 3)
        try fixture.store.save(cached, for: CacheKey(owner: "wallet", network: .mainnet))
        let (pending, release) = AsyncStream<Void>.makeStream()
        defer { release.finish() }
        let http = AssetResponses { request in
            if request.page == 1 { for await _ in pending {} }
            return try page(for: request, assets: request.page == 1 ? [asset(units: 9_007_199_254_740_993)] : [])
        }
        let service = Portfolio(rpc: http.client, store: fixture.store, pageSize: 1)
        let updates = await service.updates(for: "wallet")
        var iterator = updates.makeAsyncIterator()

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
        let requests = await http.requests
        #expect(requests.map(\.page) == [1, 2])
        #expect(requests.map(\.includesNativeBalance) == [true, false])
    }

    /// Verifies that malformed image metadata doesn't stop holdings or later pages from reaching the portfolio.
    ///
    /// This integration fixture exercises RPC decoding before the portfolio
    /// consumes the response, reproducing the original failure across both modules.
    ///
    /// - Throws: A decoding error or failed test prerequisite.
    @Test
    func `Portfolio keeps holdings and later pages when an asset image is malformed`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let http = AssetResponses { request in
            if request.page == 1 {
                let data = Data(#"""
                    {"page":1,"limit":2,"items":[
                        {"id":"fungible-asset","interface":"FungibleAsset",
                         "content":{"metadata":{"name":"Example Fungible","symbol":false},
                                    "links":{"image":false},"files":[{"uri":false,"mime":"image/png"}]},
                         "token_info":{"balance":1,"decimals":0}},
                        {"id":"first-mint","interface":"FungibleToken",
                         "token_info":{"balance":42,"decimals":6}}
                    ],"nativeBalance":{"lamports":100}}
                    """#.utf8)
                return data
            }
            return try page(for: request, assets: request.page == 2 ? [asset(units: 7)] : [])
        }
        let service = Portfolio(rpc: http.client, store: fixture.store, pageSize: 2)
        let updates = await service.updates(for: "wallet")
        var iterator = updates.makeAsyncIterator()
        _ = try #require(await iterator.next())

        let updated = try #require(await iterator.next())
        let result = try #require(updated.snapshot)

        #expect(updated.error == nil)
        #expect(!updated.isRefreshing)
        #expect(result.holdings.map(\.id) == [.nativeSOL, .asset("fungible-asset"), .asset("first-mint"), .asset("mint")])
        #expect(result.holdings.map(\.amount) == [
            Amount(units: 100, decimals: 9), Amount(units: 1, decimals: 0),
            Amount(units: 42, decimals: 6), Amount(units: 7, decimals: 6),
        ])
        let fungible = try #require(result.holdings.first { $0.id == .asset("fungible-asset") })
        #expect(fungible.name == "Example Fungible")
        #expect(fungible.imageURL == nil)
        #expect(await http.requests.map(\.page) == [1, 2, 3])
        #expect(fixture.store.snapshot(for: CacheKey(owner: "wallet", network: .mainnet)) == result)
        #expect(await iterator.next() == nil)
    }

    /// Verifies that an initial failure reports an error without inventing a zero portfolio.
    ///
    /// - Throws: A failed test prerequisite.
    @Test
    func `An uncached offline wallet keeps an absent snapshot`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let http = AssetResponses { _ in throw URLError(.notConnectedToInternet) }
        let service = Portfolio(rpc: http.client, store: fixture.store)
        let updates = await service.updates(for: "wallet")
        var iterator = updates.makeAsyncIterator()

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
    @Test
    func `A failed later page preserves the previous complete snapshot`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let cached = snapshot(owner: "wallet", network: .mainnet, units: 3)
        let key = CacheKey(owner: "wallet", network: .mainnet)
        try fixture.store.save(cached, for: key)
        let http = AssetResponses { request in
            if request.page == 2 { throw URLError(.notConnectedToInternet) }
            return try page(for: request, assets: [asset(units: 100)])
        }
        let service = Portfolio(rpc: http.client, store: fixture.store, pageSize: 1)
        let updates = await service.updates(for: "wallet")
        var iterator = updates.makeAsyncIterator()
        _ = await iterator.next()

        let failed = try #require(await iterator.next())

        #expect(failed.snapshot == cached)
        #expect(failed.error as? RPCError == .transport(.notConnectedToInternet))
        #expect(fixture.store.snapshot(for: key) == cached)
    }

    /// Verifies that unavailable storage doesn't hide a complete network result.
    ///
    /// - Parameter cachedUnits: The preceding balance, or `nil` for an uncached wallet.
    /// - Throws: A failed test prerequisite.
    @Test(arguments: [nil, UInt64(3)])
    func `Cache write failures retain freshly retrieved holdings`(cachedUnits: UInt64?) async throws {
        let cached = cachedUnits.map { snapshot(owner: "wallet", network: .mainnet, units: $0) }
        let store = WriteFailingStore(cached: cached)
        let http = AssetResponses { request in try page(for: request, assets: []) }
        let service = Portfolio(rpc: http.client, store: store)
        let updates = await service.updates(for: "wallet")
        var iterator = updates.makeAsyncIterator()
        let initial = try #require(await iterator.next())
        #expect(initial.snapshot == cached)

        let updated = try #require(await iterator.next())

        #expect(updated.holdings.first?.amount == Amount(units: 100, decimals: 9))
        #expect((updated.error as? CocoaError)?.code == .fileWriteOutOfSpace)
        #expect(!updated.isRefreshing)
        #expect(updated.revision > initial.revision)
        #expect(try #require(updated.snapshotRevision) > (initial.snapshotRevision ?? 0))
        #expect(await iterator.next() == nil)

        var retry = await service.updates(for: "wallet", policy: .reload).makeAsyncIterator()
        let retrying = try #require(await retry.next())
        #expect(retrying.revision > updated.revision)
        #expect(retrying.snapshot == cached)
        #expect(retrying.snapshotRevision == initial.snapshotRevision)
        while await retry.next() != nil {}
    }

    /// Verifies that a successful empty token list removes previously held tokens.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test
    func `A successful empty wallet replaces old token holdings`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let key = CacheKey(owner: "wallet", network: .mainnet)
        try fixture.store.save(snapshot(owner: "wallet", network: .mainnet, units: 3), for: key)
        let http = AssetResponses { request in
            try page(for: request, assets: [], lamports: 0)
        }
        let service = Portfolio(rpc: http.client, store: fixture.store)
        let updates = await service.updates(for: "wallet")
        var iterator = updates.makeAsyncIterator()
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
    @Test
    func `Repeated asset pages stop the refresh without saving partial holdings`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let http = AssetResponses { request in try page(for: request, assets: [asset(units: 1)]) }
        let service = Portfolio(rpc: http.client, store: fixture.store, pageSize: 1)
        let updates = await service.updates(for: "wallet")
        var iterator = updates.makeAsyncIterator()
        _ = await iterator.next()

        let failed = try #require(await iterator.next())

        #expect(failed.error is FetchError)
        #expect(failed.snapshot == nil)
        #expect(await http.requests.count == 2)
        #expect(fixture.store.snapshot(for: CacheKey(owner: "wallet", network: .mainnet)) == nil)
    }

    /// Verifies that forgetting a wallet clears persisted data and cancels its active request.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test(.timeLimit(.minutes(1)))
    func `Removing wallet data clears its snapshot and stops its refresh`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let key = CacheKey(owner: "wallet", network: .mainnet)
        try fixture.store.save(snapshot(owner: "wallet", network: .mainnet, units: 3), for: key)
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (cancelled, cancelledContinuation) = AsyncStream<Void>.makeStream()
        defer { release.finish(); startedContinuation.finish(); cancelledContinuation.finish() }
        let http = AssetResponses { request in
            startedContinuation.yield(())
            for await _ in pending {}
            if Task.isCancelled { cancelledContinuation.yield(()) }
            return try page(for: request, assets: [asset(units: 100)])
        }
        let service = Portfolio(rpc: http.client, store: fixture.store)
        let updates = await service.updates(for: "wallet")
        var iterator = updates.makeAsyncIterator()
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

    /// Verifies that immediate removal closes the returned stream without restoring saved holdings.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test(.timeLimit(.minutes(1)))
    func `Removing wallet data immediately after subscribing leaves no saved snapshot`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let key = CacheKey(owner: "wallet", network: .mainnet)
        try fixture.store.save(snapshot(owner: "wallet", network: .mainnet, units: 3), for: key)
        let (pending, release) = AsyncStream<Void>.makeStream()
        defer { release.finish() }
        let http = AssetResponses { request in
            for await _ in pending {}
            return try page(for: request, assets: [])
        }
        let service: any PortfolioProviding = Portfolio(rpc: http.client, store: fixture.store)
        let updates = await service.updates(for: "wallet")

        try await service.removeData(for: "wallet")
        release.finish()

        for await update in updates { #expect(update.isRefreshing) }
        #expect(fixture.store.snapshot(for: key) == nil)
    }

    /// Verifies disk reuse by a new service while keeping wallet and network identities separate.
    ///
    /// - Parameters:
    ///   - network: The network of the recreated service.
    ///   - owner: The requested wallet.
    ///   - expectedUnits: The amount belonging only to this wallet and network.
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test(arguments: [
        (Network.mainnet, "wallet-a", UInt64(11)),
        (.devnet, "wallet-a", UInt64(22)),
        (.mainnet, "wallet-b", UInt64(33)),
    ])
    func `Persisted snapshots stay isolated by wallet and network`(network: Network, owner: String, expectedUnits: UInt64) async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        for (savedNetwork, savedOwner, units) in [(Network.mainnet, "wallet-a", UInt64(11)), (.devnet, "wallet-a", 22), (.mainnet, "wallet-b", 33)] {
            try fixture.store.save(snapshot(owner: savedOwner, network: savedNetwork, units: units),
                                   for: CacheKey(owner: savedOwner, network: savedNetwork))
        }
        let http = AssetResponses(network: network) { _ in throw URLError(.notConnectedToInternet) }
        let recreatedStore = FileSnapshotStore(directory: fixture.directory)
        let service = Portfolio(rpc: http.client, store: recreatedStore)
        let updates = await service.updates(for: owner)
        var iterator = updates.makeAsyncIterator()

        let initial = try #require(await iterator.next())
        let failed = try #require(await iterator.next())

        #expect(initial.snapshot?.owner == owner)
        #expect(initial.snapshot?.network == network)
        #expect(initial.holdings.first?.amount?.units == expectedUnits)
        #expect(failed.snapshot == initial.snapshot)
    }

    /// Verifies that ending the final subscription stops networking while retaining cached holdings.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test(.timeLimit(.minutes(1)))
    func `Cancelling the last consumer stops its request and preserves cached holdings`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let key = CacheKey(owner: "wallet", network: .mainnet)
        let cached = snapshot(owner: "wallet", network: .mainnet, units: 3)
        try fixture.store.save(cached, for: key)
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (cancelled, cancelledContinuation) = AsyncStream<Void>.makeStream()
        defer { release.finish(); startedContinuation.finish(); cancelledContinuation.finish() }
        let http = AssetResponses { request in
            startedContinuation.yield(())
            for await _ in pending {}
            if Task.isCancelled { cancelledContinuation.yield(()) }
            try Task.checkCancellation()
            return try page(for: request, assets: [])
        }
        let service: any PortfolioProviding = Portfolio(rpc: http.client, store: fixture.store)
        let consumer = Task { @concurrent in
            let updates = await service.updates(for: "wallet")
            for await _ in updates {}
        }
        defer { consumer.cancel() }
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())

        consumer.cancel()
        await consumer.value

        var cancelledIterator = cancelled.makeAsyncIterator()
        _ = try #require(await cancelledIterator.next())
        #expect(await http.requests.count == 1)
        #expect(fixture.store.snapshot(for: key) == cached)
    }

    /// Verifies that cancelling one consumer leaves another consumer's shared refresh running.
    ///
    /// - Throws: A failed test prerequisite.
    @Test(.timeLimit(.minutes(1)))
    func `Concurrent consumers share a refresh when one cancels`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (observed, observedContinuation) = AsyncStream<Void>.makeStream()
        defer { release.finish(); startedContinuation.finish(); observedContinuation.finish() }
        let http = AssetResponses { request in
            if request.page == 1 {
                startedContinuation.yield(())
                for await _ in pending {}
                try Task.checkCancellation()
            }
            return try page(for: request, assets: request.page == 1 ? [asset(units: 7)] : [])
        }
        let service = Portfolio(rpc: http.client, store: fixture.store)
        let first = Task {
            let updates = await service.updates(for: "wallet")
            for await _ in updates { observedContinuation.yield(()) }
        }
        defer { first.cancel() }
        var observedIterator = observed.makeAsyncIterator()
        _ = try #require(await observedIterator.next())
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())
        let updates = await service.updates(for: "wallet")
        var second = updates.makeAsyncIterator()
        _ = try #require(await second.next())
        #expect(await http.requests.count == 1)

        first.cancel()
        await first.value
        release.finish()

        let updated = try #require(await second.next())
        #expect(updated.holdings.first { $0.id == .asset("mint") }?.amount?.units == 7)
        #expect(updated.error == nil)
        #expect(await second.next() == nil)
        #expect(await http.requests.count == 2)
    }
}

/// A real disk store isolated to one test invocation.
private struct Fixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var store: FileSnapshotStore { FileSnapshotStore(directory: directory) }

    /// Removes only this test's temporary files.
    func removeFiles() { try? FileManager.default.removeItem(at: directory) }
}

/// A snapshot store that simulates unavailable disk space.
private struct WriteFailingStore: SnapshotStoring {
    let cached: Snapshot?

    /// Returns the preceding snapshot without accessing the file system.
    ///
    /// - Parameter key: The wallet and network being read.
    /// - Returns: The fixture's preceding snapshot.
    func snapshot(for key: CacheKey) -> Snapshot? { cached }

    /// Rejects a write because the simulated disk is full.
    ///
    /// - Parameters:
    ///   - snapshot: The new snapshot that couldn't be saved.
    ///   - key: The wallet and network being written.
    /// - Throws: The file-system out-of-space error.
    func save(_ snapshot: Snapshot, for key: CacheKey) throws { throw CocoaError(.fileWriteOutOfSpace) }

    /// Rejects removal from this immutable test store.
    ///
    /// - Parameter key: The wallet and network being removed.
    /// - Throws: The file-system write-permission error.
    func remove(for key: CacheKey) throws { throw CocoaError(.fileWriteNoPermission) }
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
///   - lamports: The native balance returned when requested.
/// - Returns: A JSON DAS page.
/// - Throws: A JSON encoding error.
private func page(for request: GetFungibleAssetsByOwner, assets: [Asset], lamports: UInt64 = 100) throws -> Data {
    var value: [String: Any] = ["last_indexed_slot": 12345, "page": request.page, "limit": request.limit,
        "items": assets.map { ["id": $0.id, "interface": $0.interface,
            "token_info": ["balance": $0.balance as Any? ?? NSNull(), "decimals": $0.decimals as Any? ?? NSNull()]] }]
    if request.includesNativeBalance { value["nativeBalance"] = ["lamports": lamports] }
    return try JSONSerialization.data(withJSONObject: value)
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
