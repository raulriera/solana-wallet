import Foundation
import RPC
import Transactions
import Testing
@testable import Portfolio

struct PriceRefreshTests {
    @Test
    func `A refresh values new holdings and shares SOL's quote with Wrapped SOL`() async throws {
        let fixture = PricingFixture()
        defer { fixture.removeFiles() }
        let stalePrice = Valuation(pricePerUnit: 20, total: 20, currency: "USD")
        try fixture.store.save(Snapshot(owner: testWallet, network: .mainnet, holdings: [
            Holding(id: .asset(usdtMint), amount: Amount(units: 1, decimals: 6), name: "Tether USD", symbol: "USDT",
                    imageURL: nil, valuation: stalePrice),
        ]), for: fixture.key)
        let accounts = AccountResponses { _ in
            Ledger(lamports: 1_000_000_000, tokens: [usdcMint: 3_000_000, nativeMint: 2_000_000_000])
        }
        let prices = PriceResponses { _ in Data(#"{"\#(nativeMint)":{"usdPrice":100},"\#(usdcMint)":{"usdPrice":4}}"#.utf8) }
        let service = fixture.portfolio(rpc: accounts.client, prices: prices.client)
        let wrapped = ListedToken(mint: try Address(nativeMint), program: .token, decimals: 9, symbol: "WSOL",
                                  name: "Wrapped SOL")
        try await service.addToken(wrapped, for: testWallet)
        var updates = await service.updates(for: testWallet).makeAsyncIterator()
        _ = try #require(await updates.next())
        let update = try #require(await updates.next())
        if let error = update.error { throw error }
        let snapshot = try #require(update.snapshot)

        #expect(snapshot.holdings.map(\.id) == [.nativeSOL, .asset(usdcMint), .asset(usdtMint), .asset(nativeMint)])
        #expect(snapshot.holdings.map(\.valuation?.total) == [100, 12, nil, 200])
        #expect(snapshot.holdings.map(\.valuation?.currency) == ["USD", "USD", nil, "USD"])
        #expect(await prices.requests == [[nativeMint, usdcMint, usdtMint]])
        #expect(await accounts.requests.count == 1)
        #expect(fixture.store.snapshot(for: fixture.key) == snapshot)
        #expect(await updates.next() == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func `A refresh looks up logos and prices while it reads balances`() async throws {
        let fixture = PricingFixture()
        defer { fixture.removeFiles() }
        let (lookups, lookupStarted) = AsyncStream<Void>.makeStream()
        defer { lookupStarted.finish() }
        let accounts = AccountResponses(logos: { _ in
            lookupStarted.yield(())
            return [usdcMint: "https://cdn.example.com/usdc.png"]
        }) { _ in
            var started = lookups.makeAsyncIterator()
            _ = await started.next()
            _ = await started.next()
            return freshLedger
        }
        let prices = PriceResponses { _ in
            lookupStarted.yield(())
            return Data(#"{"\#(usdcMint)":{"usdPrice":4}}"#.utf8)
        }
        let service = fixture.portfolio(rpc: accounts.heliusClient, prices: prices.client)
        var updates = await service.updates(for: testWallet).makeAsyncIterator()
        _ = try #require(await updates.next())
        let update = try #require(await updates.next())
        if let error = update.error { throw error }
        let snapshot = try #require(update.snapshot)

        #expect(snapshot.holdings.map(\.amount?.units) == [1_000_000_000, 3_000_000, 0])
        #expect(snapshot.holdings.map(\.imageURL) == [nil, URL(string: "https://cdn.example.com/usdc.png"), nil])
        #expect(snapshot.holdings.map(\.valuation?.total) == [nil, 12, nil])
        #expect(await accounts.requests.count == 1)
        #expect(await accounts.logoRequests.count == 1)
        #expect(await prices.requests.count == 1)
    }

    @Test
    func `Price failures preserve the cached snapshot without retrying`() async throws {
        let fixture = PricingFixture()
        defer { fixture.removeFiles() }
        let cached = pricingSnapshot()
        try fixture.store.save(cached, for: fixture.key)
        let accounts = AccountResponses { _ in freshLedger }
        let prices = PriceResponses(status: 429) { _ in Data("{}".utf8) }
        let service = fixture.portfolio(rpc: accounts.client, prices: prices.client)
        var updates = await service.updates(for: testWallet).makeAsyncIterator()
        _ = try #require(await updates.next())
        let failed = try #require(await updates.next())
        #expect(failed.error as? RPCError == .http(statusCode: 429, retryAfter: "2"))
        #expect(failed.snapshot == cached)
        #expect(fixture.store.snapshot(for: fixture.key) == cached)
        #expect(await prices.requests.count == 1)
        #expect(await accounts.requests.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Concurrent reloads share one balance read and one price lookup`() async throws {
        let fixture = PricingFixture()
        defer { fixture.removeFiles() }
        let cached = pricingSnapshot()
        try fixture.store.save(cached, for: fixture.key)
        let (pending, release) = AsyncStream<Void>.makeStream()
        defer { release.finish() }
        let accounts = AccountResponses { _ in freshLedger }
        let prices = PriceResponses { _ in
            for await _ in pending {}
            return Data("{}".utf8)
        }
        let service = fixture.portfolio(rpc: accounts.client, prices: prices.client)
        var first = await service.updates(for: testWallet).makeAsyncIterator()
        #expect(try #require(await first.next()).isRefreshing)
        var second = await service.updates(for: testWallet).makeAsyncIterator()
        #expect(try #require(await second.next()).snapshot == cached)
        release.finish()
        let firstResult = try #require(await first.next())
        let secondResult = try #require(await second.next())
        #expect(firstResult.error == nil)
        #expect(firstResult.snapshot == secondResult.snapshot)
        #expect(firstResult.revision == secondResult.revision)
        #expect(firstResult.snapshotRevision == secondResult.snapshotRevision)
        #expect(await accounts.requests.count == 1)
        #expect(await prices.requests.count == 1)
        #expect(await first.next() == nil)
        #expect(await second.next() == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Removing a portfolio during its price lookup prevents cache restoration`() async throws {
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
        var updates = await service.updates(for: testWallet).makeAsyncIterator()
        _ = try #require(await updates.next())
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())
        try await service.removeData(for: testWallet)
        var cancelledIterator = cancelled.makeAsyncIterator()
        _ = try #require(await cancelledIterator.next())
        #expect(await updates.next() == nil)
        #expect(fixture.store.snapshot(for: fixture.key) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func `A refresh during a provider change can't save the previous logos`() async throws {
        let fixture = PricingFixture()
        defer { fixture.removeFiles() }
        let cached = pricingSnapshot()
        try fixture.store.save(cached, for: fixture.key)
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, announce) = AsyncStream<Void>.makeStream()
        let (cancelled, cancelledContinuation) = AsyncStream<Void>.makeStream()
        defer { release.finish(); announce.finish(); cancelledContinuation.finish() }
        let accounts = AccountResponses { _ in freshLedger }
        let prices = PriceResponses { _ in
            announce.yield(())
            for await _ in pending {}
            if Task.isCancelled { cancelledContinuation.yield(()) }
            return Data(#"{"mint":{"usdPrice":0.1}}"#.utf8)
        }
        let service = fixture.portfolio(rpc: accounts.client, prices: prices.client)
        var updates = await service.updates(for: testWallet).makeAsyncIterator()
        _ = try #require(await updates.next())
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())

        try await service.providerDidChange()

        var cancelledIterator = cancelled.makeAsyncIterator()
        _ = try #require(await cancelledIterator.next())
        #expect(await updates.next() == nil)
        let saved = try #require(fixture.store.snapshot(for: fixture.key))
        #expect(saved.holdings.allSatisfy { $0.imageURL == nil })
        #expect(saved.holdings.map(\.amount) == cached.holdings.map(\.amount))
        #expect(saved.holdings.map(\.valuation) == cached.holdings.map(\.valuation))
    }
}

private struct PricingFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let key = CacheKey(owner: testWallet, network: .mainnet)
    var store: FileSnapshotStore { FileSnapshotStore(directory: directory) }

    func portfolio(rpc: any RPC, prices: (any PriceProviding)?) -> Portfolio {
        Portfolio(rpc: rpc, store: store, tokenLists: isolatedTokenLists(), prices: prices)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: directory) }
}

private let freshLedger = Ledger(lamports: 1_000_000_000, tokens: [usdcMint: 3_000_000])

private func pricingSnapshot() -> Snapshot {
    let holdings = [
        Holding(id: .nativeSOL, amount: Amount(units: 1_000_000_000, decimals: 9), name: "Solana", symbol: "SOL",
                imageURL: nil, valuation: nil),
        Holding(id: .asset(nativeMint), amount: Amount(units: 2_000_000_000, decimals: 9), name: "Wrapped SOL",
                symbol: "WSOL", imageURL: nil, valuation: nil),
        Holding(id: .asset("mint"), amount: Amount(units: 1_250_000, decimals: 6), name: "Token", symbol: "TOK",
                imageURL: URL(string: "https://example.com/token.png"), valuation: nil),
        Holding(id: .asset("missing"), amount: Amount(units: 1, decimals: 0), name: nil, symbol: nil, imageURL: nil,
                valuation: Valuation(pricePerUnit: 20, total: 20, currency: "USDC")),
    ]
    return Snapshot(owner: testWallet, network: .mainnet, holdings: holdings)
}
