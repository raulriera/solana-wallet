import Foundation
import RPC
import Testing
import Transactions
@testable import Portfolio

struct PriceRefreshTests {
    @Test
    func `A refresh values new holdings and shares SOL's quote with Wrapped SOL`() async throws {
        let fixture = PricingFixture()
        defer { fixture.removeFiles() }
        let stalePrice = Valuation(pricePerUnit: 20, total: 20, currency: "USD")
        try fixture.store.save(Snapshot(owner: testWallet, network: .mainnet, holdings: [
            .fixture(.fixture(usdtMint, decimals: 6), amount: 1, valuation: stalePrice),
        ]), for: fixture.key)
        let accounts = AccountResponses { _ in
            Ledger(lamports: 1_000_000_000, tokens: [usdcMint: 3_000_000, nativeMint: 2_000_000_000])
        }
        let prices = PriceResponses { _ in Data(#"{"\#(nativeMint)":{"usdPrice":100},"\#(usdcMint)":{"usdPrice":4}}"#.utf8) }
        let service = fixture.portfolio(rpc: accounts.client, prices: prices.client)
        try await service.addToken(.fixture(nativeMint, decimals: 9), for: testWallet)
        var updates = await service.updates(for: testWallet).makeAsyncIterator()
        _ = try #require(await updates.next())
        let update = try #require(await updates.next())
        if let error = update.error { throw error }
        let snapshot = try #require(update.snapshot)

        let tokens = try [usdcMint, usdtMint, nativeMint].map { Asset.ID.token(mint: try Address($0)) }
        #expect(snapshot.holdings.map(\.id) == [.nativeSOL] + tokens)
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

        #expect(snapshot.holdings.map(\.balance?.amount) == [1_000_000_000, 3_000_000, 0])
        #expect(snapshot.holdings.map(\.imageURL) == [nil, URL(string: "https://cdn.example.com/usdc.png"), nil])
        #expect(snapshot.holdings.map(\.valuation?.total) == [nil, 12, nil])
        #expect(await accounts.requests.count == 1)
        #expect(await accounts.logoRequests.count == 1)
        #expect(await prices.requests.count == 1)
    }

    @Test(arguments: [
        (Valuation(pricePerUnit: 2, total: 2, currency: "USD", dayChange: 0.5),
         [nil, Valuation(pricePerUnit: 2, total: 6, currency: "USD", dayChange: 0.5), nil]),
        (nil, [nil, nil, nil]),
    ] as [(Valuation?, [Valuation?])])
    func `A price failure saves new balances at their cached prices without retrying`(
        cachedPrice: Valuation?, valuations: [Valuation?]
    ) async throws {
        let fixture = PricingFixture()
        defer { fixture.removeFiles() }
        if let cachedPrice {
            try fixture.store.save(Snapshot(owner: testWallet, network: .mainnet, holdings: [
                .fixture(.fixture(usdcMint, decimals: 6), amount: 1_000_000, valuation: cachedPrice),
            ]), for: fixture.key)
        }
        let accounts = AccountResponses { _ in freshLedger }
        let prices = PriceResponses(status: 429) { _ in Data("{}".utf8) }
        let service = fixture.portfolio(rpc: accounts.client, prices: prices.client)
        var updates = await service.updates(for: testWallet).makeAsyncIterator()
        _ = try #require(await updates.next())
        let failed = try #require(await updates.next())

        #expect(failed.error as? RPCError == .http(statusCode: 429, retryAfter: "2"))
        let snapshot = try #require(failed.snapshot)
        #expect(snapshot.holdings.map(\.balance?.amount) == [1_000_000_000, 3_000_000, 0])
        #expect(snapshot.holdings.map(\.valuation) == valuations)
        #expect(fixture.store.snapshot(for: fixture.key) == snapshot)
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
            return Data(#"{"\#(pyusdMint)":{"usdPrice":0.1}}"#.utf8)
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
        #expect(saved.holdings.map(\.balance) == cached.holdings.map(\.balance))
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
        Holding(asset: .nativeSOL, balance: TokenAmount(lamports: 1_000_000_000),
                imageURL: nil, valuation: nil),
        .fixture(.fixture(nativeMint, decimals: 9), amount: 2_000_000_000),
        .fixture(.fixture(pyusdMint, decimals: 6), amount: 1_250_000,
                 imageURL: URL(string: "https://example.com/token.png")),
        .fixture(.fixture(usdtMint, decimals: 0), amount: 1,
                 valuation: Valuation(pricePerUnit: 20, total: 20, currency: "USDC")),
    ]
    return Snapshot(owner: testWallet, network: .mainnet, holdings: holdings)
}
