import Foundation
@testable import RPC
import Testing
import Transactions
@testable import Portfolio

/// Tests complete cache-and-refresh cycles with real RPC decoding, HTTP fixtures, and isolated disk stores.
struct PortfolioTests {
    /// Verifies immediate reuse, one balance read for the wallet and its listed tokens, and persistence.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test(.timeLimit(.minutes(1)))
    func `Cached holdings arrive before a complete refreshed portfolio`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let key = CacheKey(owner: testWallet, network: .mainnet)
        let cached = snapshot(owner: testWallet, network: .mainnet, units: 3)
        try fixture.store.save(cached, for: key)
        let (pending, release) = AsyncStream<Void>.makeStream()
        defer { release.finish() }
        let http = AccountResponses { _ in
            for await _ in pending {}
            return Ledger(lamports: 100, tokens: [usdcMint: 9_007_199_254_740_993])
        }
        let service = fixture.portfolio(rpc: http.client)
        let updates = await service.updates(for: testWallet)
        var iterator = updates.makeAsyncIterator()

        let initial = try #require(await iterator.next())
        #expect(initial.snapshot == cached)
        #expect(initial.isRefreshing)
        release.finish()
        let updated = try #require(await iterator.next())
        let result = try #require(updated.snapshot)

        #expect(result.holdings.map(\.id) == [.nativeSOL, .asset(usdcMint), .asset(usdtMint)])
        #expect(result.holdings.map(\.symbol) == ["SOL", "USDC", "USDT"])
        #expect(result.holdings.map(\.amount) == [Amount(units: 100, decimals: 9),
                                                  Amount(units: 9_007_199_254_740_993, decimals: 6),
                                                  Amount(units: 0, decimals: 6)])
        #expect(result.unpricedHoldingCount == 3)
        #expect(!updated.isRefreshing)
        #expect(updated.error == nil)
        #expect(fixture.store.snapshot(for: key) == result)
        #expect(await iterator.next() == nil)
        let wallet = try Address(testWallet)
        let tokenAccounts = try [usdcMint, usdtMint].map {
            try TokenProgram.token.associatedAccount(owner: wallet, mint: Address($0)).value
        }
        #expect(await http.requests == [[testWallet] + tokenAccounts])
    }

    /// Verifies a Token-2022 token's balance comes from the associated account of its own program.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test
    func `Token-2022 balances come from their own associated accounts`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let mint = "2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo"
        let http = AccountResponses { _ in Ledger(lamports: 1, tokens: [mint: 42]) }
        let service = fixture.portfolio(rpc: http.client)
        let token = ListedToken(mint: try Address(mint), program: .token2022, decimals: 6, symbol: "PYUSD", name: "PayPal USD")
        _ = try await service.addToken(token, for: testWallet)
        var updates = await service.updates(for: testWallet, policy: .reload).makeAsyncIterator()
        _ = try #require(await updates.next())

        let updated = try #require(await updates.next())

        #expect(updated.error == nil)
        #expect(updated.holdings.last?.id == .asset(mint))
        #expect(updated.holdings.last?.amount == Amount(units: 42, decimals: 6))
        let tokenAccount = try TokenProgram.token2022.associatedAccount(owner: Address(testWallet), mint: Address(mint))
        #expect(await http.requests.first?.last == tokenAccount.value)
    }

    /// Verifies one token account with unexpected contents leaves only that balance unknown.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test
    func `An unreadable token account leaves only its balance unknown`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let http = AccountResponses { _ in Ledger(lamports: 100, tokens: [usdcMint: 5, usdtMint: 7], corrupt: [usdcMint]) }
        let service = fixture.portfolio(rpc: http.client)
        var updates = await service.updates(for: testWallet).makeAsyncIterator()
        _ = try #require(await updates.next())

        let updated = try #require(await updates.next())

        #expect(updated.error == nil)
        #expect(updated.holdings.map(\.amount) == [Amount(units: 100, decimals: 9), nil, Amount(units: 7, decimals: 6)])
    }

    /// Verifies that an initial failure reports an error without inventing a zero portfolio.
    ///
    /// - Throws: A failed test prerequisite.
    @Test
    func `An uncached offline wallet keeps an absent snapshot`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let http = AccountResponses { _ in throw URLError(.notConnectedToInternet) }
        let service = fixture.portfolio(rpc: http.client)
        let updates = await service.updates(for: testWallet)
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

    /// Verifies that a failed balance read never replaces a complete persisted portfolio.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test
    func `A failed balance read preserves the previous complete snapshot`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let cached = snapshot(owner: testWallet, network: .mainnet, units: 3)
        let key = CacheKey(owner: testWallet, network: .mainnet)
        try fixture.store.save(cached, for: key)
        let http = AccountResponses { _ in throw URLError(.notConnectedToInternet) }
        let service = fixture.portfolio(rpc: http.client)
        let updates = await service.updates(for: testWallet)
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
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let cached = cachedUnits.map { snapshot(owner: testWallet, network: .mainnet, units: $0) }
        let http = AccountResponses { _ in Ledger() }
        let service = fixture.portfolio(rpc: http.client, store: WriteFailingStore(cached: cached))
        let updates = await service.updates(for: testWallet)
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

        var retry = await service.updates(for: testWallet, policy: .reload).makeAsyncIterator()
        let retrying = try #require(await retry.next())
        #expect(retrying.revision > updated.revision)
        #expect(retrying.snapshot == cached)
        #expect(retrying.snapshotRevision == initial.snapshotRevision)
        while await retry.next() != nil {}
    }

    /// Verifies that a successful read replaces old balances, and that missing accounts hold nothing.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test
    func `A successful read with no accounts replaces old balances with zero`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let key = CacheKey(owner: testWallet, network: .mainnet)
        try fixture.store.save(snapshot(owner: testWallet, network: .mainnet, units: 3), for: key)
        let http = AccountResponses { _ in Ledger(lamports: nil) }
        let service = fixture.portfolio(rpc: http.client)
        let updates = await service.updates(for: testWallet)
        var iterator = updates.makeAsyncIterator()
        _ = await iterator.next()

        let updated = try #require(await iterator.next())

        #expect(updated.holdings.map(\.amount) == [Amount(units: 0, decimals: 9), Amount(units: 0, decimals: 6),
                                                   Amount(units: 0, decimals: 6)])
        #expect(updated.error == nil)
        #expect(fixture.store.snapshot(for: key) == updated.snapshot)
    }

    /// Verifies that forgetting a wallet clears persisted data and cancels its active request.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test(.timeLimit(.minutes(1)))
    func `Removing wallet data clears its snapshot and stops its refresh`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let key = CacheKey(owner: testWallet, network: .mainnet)
        try fixture.store.save(snapshot(owner: testWallet, network: .mainnet, units: 3), for: key)
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (cancelled, cancelledContinuation) = AsyncStream<Void>.makeStream()
        defer { release.finish(); startedContinuation.finish(); cancelledContinuation.finish() }
        let http = AccountResponses { _ in
            startedContinuation.yield(())
            for await _ in pending {}
            if Task.isCancelled { cancelledContinuation.yield(()) }
            return Ledger()
        }
        let service = fixture.portfolio(rpc: http.client)
        let updates = await service.updates(for: testWallet)
        var iterator = updates.makeAsyncIterator()
        _ = try #require(await iterator.next())
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())

        try await service.removeData(for: testWallet)

        #expect(await iterator.next() == nil)
        var cancelledIterator = cancelled.makeAsyncIterator()
        _ = try #require(await cancelledIterator.next())
        #expect(fixture.store.snapshot(for: key) == nil)
        try await service.removeData(for: testWallet)
    }

    /// Verifies that immediate removal closes the returned stream without restoring saved holdings.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test(.timeLimit(.minutes(1)))
    func `Removing wallet data immediately after subscribing leaves no saved snapshot`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let key = CacheKey(owner: testWallet, network: .mainnet)
        try fixture.store.save(snapshot(owner: testWallet, network: .mainnet, units: 3), for: key)
        let (pending, release) = AsyncStream<Void>.makeStream()
        defer { release.finish() }
        let http = AccountResponses { _ in
            for await _ in pending {}
            return Ledger()
        }
        let service: any PortfolioProviding = fixture.portfolio(rpc: http.client)
        let updates = await service.updates(for: testWallet)

        try await service.removeData(for: testWallet)
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
        (Network.mainnet, testWallet, UInt64(11)),
        (.devnet, testWallet, UInt64(22)),
        (.mainnet, otherWallet, UInt64(33)),
    ])
    func `Persisted snapshots stay isolated by wallet and network`(network: Network, owner: String, expectedUnits: UInt64) async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        for (savedNetwork, savedOwner, units) in [(Network.mainnet, testWallet, UInt64(11)), (.devnet, testWallet, 22),
                                                  (.mainnet, otherWallet, 33)] {
            try fixture.store.save(snapshot(owner: savedOwner, network: savedNetwork, units: units),
                                   for: CacheKey(owner: savedOwner, network: savedNetwork))
        }
        let http = AccountResponses(network: network) { _ in throw URLError(.notConnectedToInternet) }
        let service = fixture.portfolio(rpc: http.client, store: FileSnapshotStore(directory: fixture.directory))
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
        let key = CacheKey(owner: testWallet, network: .mainnet)
        let cached = snapshot(owner: testWallet, network: .mainnet, units: 3)
        try fixture.store.save(cached, for: key)
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (cancelled, cancelledContinuation) = AsyncStream<Void>.makeStream()
        defer { release.finish(); startedContinuation.finish(); cancelledContinuation.finish() }
        let http = AccountResponses { _ in
            startedContinuation.yield(())
            for await _ in pending {}
            if Task.isCancelled { cancelledContinuation.yield(()) }
            try Task.checkCancellation()
            return Ledger()
        }
        let service: any PortfolioProviding = fixture.portfolio(rpc: http.client)
        let consumer = Task { @concurrent in
            let updates = await service.updates(for: testWallet)
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
        let http = AccountResponses { _ in
            startedContinuation.yield(())
            for await _ in pending {}
            try Task.checkCancellation()
            return Ledger(tokens: [usdcMint: 7])
        }
        let service = fixture.portfolio(rpc: http.client)
        let first = Task {
            let updates = await service.updates(for: testWallet)
            for await _ in updates { observedContinuation.yield(()) }
        }
        defer { first.cancel() }
        var observedIterator = observed.makeAsyncIterator()
        _ = try #require(await observedIterator.next())
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())
        let updates = await service.updates(for: testWallet)
        var second = updates.makeAsyncIterator()
        _ = try #require(await second.next())
        #expect(await http.requests.count == 1)

        first.cancel()
        await first.value
        release.finish()

        let updated = try #require(await second.next())
        #expect(updated.holdings.first { $0.id == .asset(usdcMint) }?.amount?.units == 7)
        #expect(updated.error == nil)
        #expect(await second.next() == nil)
        #expect(await http.requests.count == 1)
    }

    /// Verifies an older cache, with tokens and metadata that DAS discovered, is absent during refresh
    /// and after a network failure.
    /// - Parameter version: An older cache format.
    /// - Throws: A cache fixture or test prerequisite error.
    @Test(arguments: [1, 2, 3])
    func `Older caches are not restored while offline`(version: Int) async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let key = CacheKey(owner: testWallet, network: .mainnet)
        try fixture.store.save(snapshot(owner: testWallet, network: .mainnet, units: 3), for: key)
        let file = try #require(FileManager.default.contentsOfDirectory(at: fixture.directory,
                                                                        includingPropertiesForKeys: nil).first)
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        envelope["version"] = version
        try JSONSerialization.data(withJSONObject: envelope).write(to: file)
        let http = AccountResponses { _ in throw URLError(.notConnectedToInternet) }
        let service = fixture.portfolio(rpc: http.client)
        var updates = await service.updates(for: testWallet).makeAsyncIterator()

        let initial = try #require(await updates.next())
        #expect(initial.snapshot == nil)
        #expect(initial.isRefreshing)
        let failed = try #require(await updates.next())
        #expect(failed.snapshot == nil)
        #expect(failed.error != nil)
        #expect(fixture.store.snapshot(for: key) == nil)
        #expect(await updates.next() == nil)
    }
}

/// Real disk stores isolated to one test invocation.
private struct Fixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var store: FileSnapshotStore { FileSnapshotStore(directory: directory) }

    /// Creates a service that keeps its snapshots and token lists in this test's directory.
    ///
    /// - Parameters:
    ///   - rpc: The client whose balance reads the service makes.
    ///   - store: A replacement snapshot store, or `nil` for this test's disk store.
    /// - Returns: The service under test.
    func portfolio(rpc: any RPC, store: (any SnapshotStoring)? = nil) -> Portfolio {
        Portfolio(rpc: rpc, store: store ?? self.store,
                  tokenLists: FileTokenListStore(directory: directory.appendingPathComponent("TokenLists")))
    }

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

/// Creates a previously retrieved portfolio fixture.
///
/// - Parameters:
///   - owner: The wallet address.
///   - network: The snapshot's network.
///   - units: The cached USDC balance.
/// - Returns: An immutable snapshot with an earlier successful retrieval time.
private func snapshot(owner: String, network: Network, units: UInt64) -> Snapshot {
    Snapshot(owner: owner, network: network,
             holdings: [Holding(id: .asset(usdcMint), amount: Amount(units: units, decimals: 6),
                                name: nil, symbol: nil, imageURL: nil, valuation: nil)],
             fetchedAt: Date(timeIntervalSince1970: 1))
}
