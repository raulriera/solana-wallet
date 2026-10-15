import Foundation
@testable import RPC
import Synchronization
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
        // Without a price provider, no holding has a value.
        #expect(result.holdings.allSatisfy { $0.valuation == nil })
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
        let mint = pyusdMint
        let http = AccountResponses { _ in Ledger(lamports: 1, tokens: [mint: 42]) }
        let service = fixture.portfolio(rpc: http.client)
        let token = ListedToken(mint: try Address(mint), program: .token2022, decimals: 6, symbol: "PYUSD", name: "PayPal USD")
        try await service.addToken(token, for: testWallet)
        var updates = await service.updates(for: testWallet).makeAsyncIterator()
        _ = try #require(await updates.next())

        let updated = try #require(await updates.next())

        #expect(updated.error == nil)
        #expect(updated.holdings.last?.id == .asset(mint))
        #expect(updated.holdings.last?.amount == Amount(units: 42, decimals: 6))
        let tokenAccount = try TokenProgram.token2022.associatedAccount(owner: Address(testWallet), mint: Address(mint))
        #expect(await http.requests.first?.last == tokenAccount.value)
    }

    /// Verifies a balance read in progress starts again when the list changes, so its consumers never get the old list.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test(.timeLimit(.minutes(1)))
    func `A balance read in progress starts again when the token list changes`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let (started, announce) = AsyncStream<Void>.makeStream()
        let (pending, release) = AsyncStream<Void>.makeStream()
        defer { announce.finish(); release.finish() }
        let http = AccountResponses { addresses in
            // Holds the read of the original list, the wallet and two default tokens, until it's cancelled.
            if addresses.count == 3 {
                announce.yield(())
                for await _ in pending {}
            }
            return Ledger(lamports: 100, tokens: [pyusdMint: 42])
        }
        let service = fixture.portfolio(rpc: http.client)
        var updates = await service.updates(for: testWallet).makeAsyncIterator()
        _ = try #require(await updates.next())
        var reading = started.makeAsyncIterator()
        _ = try #require(await reading.next())

        let token = ListedToken(mint: try Address(pyusdMint), program: .token2022, decimals: 6, symbol: "PYUSD", name: "PayPal USD")
        try await service.addToken(token, for: testWallet)
        let updated = try #require(await updates.next())

        #expect(updated.error == nil)
        #expect(updated.holdings.map(\.id) == [.nativeSOL, .asset(usdcMint), .asset(usdtMint), .asset(pyusdMint)])
        #expect(updated.holdings.last?.amount == Amount(units: 42, decimals: 6))
        #expect(await updates.next() == nil)
        #expect(await http.requests.map(\.count) == [3, 4])
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
        #expect(updated.holdings.allSatisfy { $0.otherOwner == nil })
    }

    /// Verifies a token account that another address controls names that address instead of a balance.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test
    func `A token account that another address controls names that address instead of a balance`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let http = AccountResponses { _ in
            Ledger(lamports: 100, tokens: [usdcMint: 5, usdtMint: 7], otherOwners: [usdtMint: otherWallet])
        }
        let service = fixture.portfolio(rpc: http.client)
        var updates = await service.updates(for: testWallet).makeAsyncIterator()
        _ = try #require(await updates.next())

        let updated = try #require(await updates.next())

        #expect(updated.error == nil)
        #expect(updated.holdings.map(\.amount) == [Amount(units: 100, decimals: 9), Amount(units: 5, decimals: 6), nil])
        #expect(updated.holdings.map(\.otherOwner) == [nil, nil, try Address(otherWallet)])
    }

    /// Verifies an address that received SOL before its token account exists holds none of the token.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test
    func `A prefunded associated address holds nothing until its token account exists`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let http = AccountResponses { _ in Ledger(lamports: 100, tokens: [usdtMint: 7], prefunded: [usdcMint]) }
        let service = fixture.portfolio(rpc: http.client)
        var updates = await service.updates(for: testWallet).makeAsyncIterator()
        _ = try #require(await updates.next())

        let updated = try #require(await updates.next())

        #expect(updated.error == nil)
        #expect(updated.holdings.map(\.amount) == [
            Amount(units: 100, decimals: 9), Amount(units: 0, decimals: 6), Amount(units: 7, decimals: 6),
        ])
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

        var retry = await service.updates(for: testWallet).makeAsyncIterator()
        let retrying = try #require(await retry.next())
        #expect(retrying.revision > updated.revision)
        #expect(retrying.snapshot == cached)
        #expect(retrying.snapshotRevision == initial.snapshotRevision)
        while await retry.next() != nil {}
    }

    /// Verifies a removal stands when the cached holdings can't be saved again, since the saved list holds the truth.
    ///
    /// - Throws: A failed test prerequisite.
    @Test
    func `A removal stands when cached holdings can't be saved`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let cached = snapshot(owner: testWallet, network: .mainnet, units: 3)
        let service = fixture.portfolio(rpc: AccountResponses { _ in Ledger() }.client,
                                        store: WriteFailingStore(cached: cached))

        try await service.removeToken(Address(usdcMint), for: testWallet)

        let saved = try fixture.tokenLists.tokenList(for: CacheKey(owner: testWallet, network: .mainnet))
        #expect(saved?.tokens.map(\.mint.value) == [DefaultToken.usdt.rawValue])
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

    /// Verifies listed tokens get the provider's logo copies, which later reads keep without asking again.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test(.timeLimit(.minutes(1)))
    func `Listed tokens get logos once from a provider that has them`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let http = AccountResponses(logos: { mints in
            Dictionary(uniqueKeysWithValues: mints.map { ($0, "https://cdn.example.com/\($0).png") })
        }) { _ in Ledger() }
        let service = fixture.portfolio(rpc: http.heliusClient)
        let usdcLogo = try #require(URL(string: "https://cdn.example.com/\(usdcMint).png"))
        let usdtLogo = try #require(URL(string: "https://cdn.example.com/\(usdtMint).png"))

        let first = try #require(try await reload(service).snapshot)
        let second = try #require(try await reload(service).snapshot)

        #expect(first.holdings.map(\.imageURL) == [nil, usdcLogo, usdtLogo])
        #expect(second.holdings.map(\.imageURL) == [nil, usdcLogo, usdtLogo])
        #expect(await http.logoRequests == [[usdcMint, usdtMint]])
    }

    /// Verifies a lookup asks only for tokens without a logo, so a token the provider lacks is asked for again.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test(.timeLimit(.minutes(1)))
    func `Only tokens without a logo are looked up again`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let http = AccountResponses(logos: { mints in
            mints.contains(usdcMint) ? [usdcMint: "https://cdn.example.com/usdc.png"] : [:]
        }) { _ in Ledger() }
        let service = fixture.portfolio(rpc: http.heliusClient)
        let usdcLogo = try #require(URL(string: "https://cdn.example.com/usdc.png"))

        let first = try #require(try await reload(service).snapshot)
        let second = try #require(try await reload(service).snapshot)

        #expect(first.holdings.map(\.imageURL) == [nil, usdcLogo, nil])
        #expect(second.holdings.map(\.imageURL) == [nil, usdcLogo, nil])
        #expect(await http.logoRequests == [[usdcMint, usdtMint], [usdtMint]])
    }

    /// Verifies a failed lookup keeps the balances without logos, and the next balance read asks again.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test(.timeLimit(.minutes(1)))
    func `A failed logo lookup keeps the balances and the next read asks again`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let offline = Mutex(true)
        let http = AccountResponses(logos: { _ in
            if offline.withLock({ $0 }) { throw URLError(.notConnectedToInternet) }
            return [usdcMint: "https://cdn.example.com/usdc.png"]
        }) { _ in Ledger(tokens: [usdcMint: 5]) }
        let service = fixture.portfolio(rpc: http.heliusClient)
        let usdcLogo = try #require(URL(string: "https://cdn.example.com/usdc.png"))

        let failed = try await reload(service)
        offline.withLock { $0 = false }
        let recovered = try #require(try await reload(service).snapshot)

        #expect(failed.error == nil)
        #expect(failed.snapshot?.holdings.map(\.amount) == [Amount(units: 100, decimals: 9), Amount(units: 5, decimals: 6),
                                                              Amount(units: 0, decimals: 6)])
        #expect(failed.snapshot?.holdings.allSatisfy { $0.imageURL == nil } == true)
        #expect(recovered.holdings.map(\.imageURL) == [nil, usdcLogo, nil])
        #expect(await http.logoRequests == [[usdcMint, usdtMint], [usdcMint, usdtMint]])
    }

    /// Verifies a provider without logo copies shows none, even when the cached snapshot has logos.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test(.timeLimit(.minutes(1)))
    func `A provider without logos shows none`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let logo = try #require(URL(string: "https://cdn.example.com/usdc.png"))
        let cached = Snapshot(owner: testWallet, network: .mainnet,
                              holdings: [Holding(id: .asset(usdcMint), amount: Amount(units: 1, decimals: 6),
                                                 name: "USD Coin", symbol: "USDC", imageURL: logo, valuation: nil)])
        try fixture.store.save(cached, for: CacheKey(owner: testWallet, network: .mainnet))
        let http = AccountResponses { _ in Ledger() }

        let refreshed = try #require(try await reload(fixture.portfolio(rpc: http.client)).snapshot)

        #expect(refreshed.holdings.allSatisfy { $0.imageURL == nil })
        #expect(await http.logoRequests.isEmpty)
    }

    /// Verifies a provider change removes every saved logo, keeps the balances, and lets the next read
    /// replace earlier copies and ask the new provider for logos.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test(.timeLimit(.minutes(1)))
    func `A provider change removes saved logos and keeps balances`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let host = Mutex("old.example.com")
        let http = AccountResponses(logos: { mints in
            let host = host.withLock { $0 }
            return Dictionary(uniqueKeysWithValues: mints.map { ($0, "https://\(host)/\($0).png") })
        }) { _ in Ledger(tokens: [usdcMint: 5]) }
        let service = fixture.portfolio(rpc: http.heliusClient)
        let read = try await reload(service)
        let otherKey = CacheKey(owner: otherWallet, network: .mainnet)
        let logo = try #require(URL(string: "https://old.example.com/usdc.png"))
        let other = Snapshot(owner: otherWallet, network: .mainnet,
                             holdings: [Holding(id: .asset(usdcMint), amount: Amount(units: 1, decimals: 6),
                                                name: "USD Coin", symbol: "USDC", imageURL: logo, valuation: nil)])
        try fixture.store.save(other, for: otherKey)

        try await service.providerDidChange()

        let original = try #require(read.snapshot)
        let saved = try #require(fixture.store.snapshot(for: CacheKey(owner: testWallet, network: .mainnet)))
        let otherSaved = try #require(fixture.store.snapshot(for: otherKey))
        #expect(saved.holdings.allSatisfy { $0.imageURL == nil })
        #expect(saved.holdings.map(\.amount) == original.holdings.map(\.amount))
        #expect(otherSaved.holdings.map(\.imageURL) == [nil])
        #expect(otherSaved.holdings.map(\.amount) == other.holdings.map(\.amount))
        host.withLock { $0 = "new.example.com" }
        var updates = await service.updates(for: testWallet).makeAsyncIterator()
        let initial = try #require(await updates.next())
        let refreshed = try #require(await updates.next())
        let earlierRevision = try #require(read.snapshotRevision)
        #expect(initial.snapshot == saved)
        #expect(try #require(initial.snapshotRevision) > earlierRevision)
        #expect(refreshed.holdings.compactMap { $0.imageURL?.host() } == ["new.example.com", "new.example.com"])
        #expect(await http.logoRequests == [[usdcMint, usdtMint], [usdcMint, usdtMint]])
    }

    /// Verifies a provider change with nothing saved yet leaves nothing to rewrite.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test
    func `A provider change without saved snapshots succeeds`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let http = AccountResponses { _ in Ledger() }

        try await fixture.portfolio(rpc: http.client).providerDidChange()

        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path()))
    }

    /// Verifies a provider change reports a snapshot that a full disk can't rewrite without its logos,
    /// and still ends the refresh in progress.
    ///
    /// - Throws: A fixture setup error or failed prerequisite.
    @Test(.timeLimit(.minutes(1)))
    func `A provider change reports a snapshot whose logos can't be removed and still ends its work`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let cached = snapshot(owner: testWallet, network: .mainnet, units: 3,
                              imageURL: URL(string: "https://old.example.com/usdc.png"))
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, announce) = AsyncStream<Void>.makeStream()
        defer { release.finish(); announce.finish() }
        let http = AccountResponses { _ in
            announce.yield(())
            for await _ in pending {}
            return Ledger()
        }
        let service = fixture.portfolio(rpc: http.client, store: WriteFailingStore(cached: cached))
        var updates = await service.updates(for: testWallet).makeAsyncIterator()
        _ = try #require(await updates.next())
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())

        await #expect(throws: CocoaError(.fileWriteOutOfSpace)) { try await service.providerDidChange() }

        #expect(await updates.next() == nil)
    }
}

/// Real disk stores isolated to one test invocation.
private struct Fixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var store: FileSnapshotStore { FileSnapshotStore(directory: directory) }
    /// The token-list store in this test's directory.
    var tokenLists: FileTokenListStore { FileTokenListStore(directory: directory.appendingPathComponent("TokenLists")) }

    /// Creates a service that keeps its snapshots and token lists in this test's directory.
    ///
    /// - Parameters:
    ///   - rpc: The client whose balance reads the service makes.
    ///   - store: A replacement snapshot store, or `nil` for this test's disk store.
    /// - Returns: The service under test.
    func portfolio(rpc: any RPC, store: (any SnapshotStoring)? = nil) -> Portfolio {
        Portfolio(rpc: rpc, store: store ?? self.store, tokenLists: tokenLists)
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

    /// Lists the preceding snapshot without accessing the file system.
    ///
    /// - Returns: The fixture's preceding snapshot, if any.
    func snapshots() -> [Snapshot] { cached.map { [$0] } ?? [] }

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

/// Reads the test wallet's balances again and returns the refresh's final state.
/// - Parameter service: The service to refresh.
/// - Returns: The completed or failed update that ends the refresh.
/// - Throws: A test prerequisite error if the refresh ends without a state.
private func reload(_ service: Portfolio) async throws -> Update {
    var last: Update?
    for await update in await service.updates(for: testWallet) { last = update }
    return try #require(last)
}

/// Creates a previously read portfolio fixture.
///
/// - Parameters:
///   - owner: The wallet address.
///   - network: The snapshot's network.
///   - units: The cached USDC balance.
///   - imageURL: The cached USDC logo, if any.
/// - Returns: An immutable snapshot of the USDC balance.
private func snapshot(owner: String, network: Network, units: UInt64, imageURL: URL? = nil) -> Snapshot {
    Snapshot(owner: owner, network: network,
             holdings: [Holding(id: .asset(usdcMint), amount: Amount(units: units, decimals: 6),
                                name: nil, symbol: nil, imageURL: imageURL, valuation: nil)])
}
