import Foundation
import Synchronization
import Testing
import Transactions
@testable import Portfolio
@testable import RPC

struct PortfolioTests {
    @Test(.timeLimit(.minutes(1)))
    func `Cached holdings arrive before a complete refreshed portfolio`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let key = CacheKey(owner: testWallet, network: .mainnet)
        let cached = snapshot(owner: testWallet, network: .mainnet, amount: 3)
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

        let tokens = try [usdcMint, usdtMint].map { Asset.ID.token(mint: try Address($0)) }
        #expect(result.holdings.map(\.id) == [.nativeSOL] + tokens)
        #expect(result.holdings.map(\.asset) == [
            .nativeSOL,
            .token(.fixture(usdcMint, decimals: 6, name: "USD Coin", symbol: "USDC")),
            .token(.fixture(usdtMint, decimals: 6, name: "Tether USD", symbol: "USDT")),
        ])
        #expect(result.holdings.map(\.balance) == [TokenAmount(lamports: 100),
                                                  TokenAmount(amount: 9_007_199_254_740_993, decimals: 6),
                                                  TokenAmount(amount: 0, decimals: 6)])
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

    @Test
    func `Token-2022 balances come from their own associated accounts`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let mint = pyusdMint
        let http = AccountResponses { _ in Ledger(lamports: 1, tokens: [mint: 42]) }
        let service = fixture.portfolio(rpc: http.client)
        try await service.addToken(.fixture(pyusdMint, program: .token2022, decimals: 6), for: testWallet)
        var updates = await service.updates(for: testWallet).makeAsyncIterator()
        _ = try #require(await updates.next())

        let updated = try #require(await updates.next())

        #expect(updated.error == nil)
        #expect(try updated.holdings.last?.id == .token(mint: Address(mint)))
        #expect(updated.holdings.last?.balance == TokenAmount(amount: 42, decimals: 6))
        let tokenAccount = try TokenProgram.token2022.associatedAccount(owner: Address(testWallet), mint: Address(mint))
        #expect(await http.requests.first?.last == tokenAccount.value)
    }

    @Test(.timeLimit(.minutes(1)))
    func `A balance read in progress starts again when the token list changes`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let (started, announce) = AsyncStream<Void>.makeStream()
        let (pending, release) = AsyncStream<Void>.makeStream()
        defer { announce.finish(); release.finish() }
        let http = AccountResponses { addresses in
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

        try await service.addToken(.fixture(pyusdMint, program: .token2022, decimals: 6), for: testWallet)
        let updated = try #require(await updates.next())

        #expect(updated.error == nil)
        let tokens = try [usdcMint, usdtMint, pyusdMint].map { Asset.ID.token(mint: try Address($0)) }
        #expect(updated.holdings.map(\.id) == [.nativeSOL] + tokens)
        #expect(updated.holdings.last?.balance == TokenAmount(amount: 42, decimals: 6))
        #expect(await updates.next() == nil)
        #expect(await http.requests.map(\.count) == [3, 4])
    }

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
        #expect(updated.holdings.map(\.balance) == [TokenAmount(lamports: 100), nil, TokenAmount(amount: 7, decimals: 6)])
        #expect(updated.holdings.allSatisfy { $0.otherOwner == nil })
    }

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
        #expect(updated.holdings.map(\.balance) == [TokenAmount(lamports: 100), TokenAmount(amount: 5, decimals: 6), nil])
        #expect(updated.holdings.map(\.otherOwner) == [nil, nil, try Address(otherWallet)])
    }

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
        #expect(updated.holdings.map(\.balance) == [
            TokenAmount(lamports: 100), TokenAmount(amount: 0, decimals: 6), TokenAmount(amount: 7, decimals: 6),
        ])
    }

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

    @Test
    func `A failed balance read preserves the previous complete snapshot`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let cached = snapshot(owner: testWallet, network: .mainnet, amount: 3)
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

    @Test(arguments: [nil, UInt64(3)])
    func `Cache write failures retain freshly retrieved holdings`(cachedAmount: UInt64?) async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let cached = cachedAmount.map { snapshot(owner: testWallet, network: .mainnet, amount: $0) }
        let http = AccountResponses { _ in Ledger() }
        let service = fixture.portfolio(rpc: http.client, store: WriteFailingStore(cached: cached))
        let updates = await service.updates(for: testWallet)
        var iterator = updates.makeAsyncIterator()
        let initial = try #require(await iterator.next())
        #expect(initial.snapshot == cached)

        let updated = try #require(await iterator.next())

        #expect(updated.holdings.first?.balance == TokenAmount(lamports: 100))
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

    @Test
    func `A removal stands when cached holdings can't be saved`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let cached = snapshot(owner: testWallet, network: .mainnet, amount: 3)
        let service = fixture.portfolio(rpc: AccountResponses { _ in Ledger() }.client,
                                        store: WriteFailingStore(cached: cached))

        try await service.removeToken(Address(usdcMint), for: testWallet)

        let saved = try fixture.tokenLists.tokenList(for: CacheKey(owner: testWallet, network: .mainnet))
        #expect(saved?.mints.map(\.address.value) == [usdtMint])
    }

    @Test
    func `A successful read with no accounts replaces old balances with zero`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let key = CacheKey(owner: testWallet, network: .mainnet)
        try fixture.store.save(snapshot(owner: testWallet, network: .mainnet, amount: 3), for: key)
        let http = AccountResponses { _ in Ledger(lamports: nil) }
        let service = fixture.portfolio(rpc: http.client)
        let updates = await service.updates(for: testWallet)
        var iterator = updates.makeAsyncIterator()
        _ = await iterator.next()

        let updated = try #require(await iterator.next())

        #expect(updated.holdings.map(\.balance) == [TokenAmount(lamports: 0), TokenAmount(amount: 0, decimals: 6),
                                                   TokenAmount(amount: 0, decimals: 6)])
        #expect(updated.error == nil)
        #expect(fixture.store.snapshot(for: key) == updated.snapshot)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Removing wallet data clears its snapshot and stops its refresh`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let key = CacheKey(owner: testWallet, network: .mainnet)
        try fixture.store.save(snapshot(owner: testWallet, network: .mainnet, amount: 3), for: key)
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

    @Test(.timeLimit(.minutes(1)))
    func `Removing wallet data immediately after subscribing leaves no saved snapshot`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let key = CacheKey(owner: testWallet, network: .mainnet)
        try fixture.store.save(snapshot(owner: testWallet, network: .mainnet, amount: 3), for: key)
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

    @Test(arguments: [
        (Network.mainnet, testWallet, UInt64(11)),
        (.devnet, testWallet, UInt64(22)),
        (.mainnet, otherWallet, UInt64(33)),
    ])
    func `Persisted snapshots stay isolated by wallet and network`(network: Network, owner: String, expectedAmount: UInt64) async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        for (savedNetwork, savedOwner, amount) in [(Network.mainnet, testWallet, UInt64(11)), (.devnet, testWallet, 22),
                                                  (.mainnet, otherWallet, 33)] {
            try fixture.store.save(snapshot(owner: savedOwner, network: savedNetwork, amount: amount),
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
        #expect(initial.holdings.first?.balance?.amount == expectedAmount)
        #expect(failed.snapshot == initial.snapshot)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Cancelling the last consumer stops its request and preserves cached holdings`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let key = CacheKey(owner: testWallet, network: .mainnet)
        let cached = snapshot(owner: testWallet, network: .mainnet, amount: 3)
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
        let usdc = Asset.ID.token(mint: try Address(usdcMint))
        #expect(updated.holdings.first { $0.id == usdc }?.balance?.amount == 7)
        #expect(updated.error == nil)
        #expect(await second.next() == nil)
        #expect(await http.requests.count == 1)
    }

    @Test(arguments: [1, 2, 3])
    func `Older caches are not restored while offline`(version: Int) async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let key = CacheKey(owner: testWallet, network: .mainnet)
        try fixture.store.save(snapshot(owner: testWallet, network: .mainnet, amount: 3), for: key)
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
        #expect(failed.snapshot?.holdings.map(\.balance) == [TokenAmount(lamports: 100), TokenAmount(amount: 5, decimals: 6),
                                                              TokenAmount(amount: 0, decimals: 6)])
        #expect(failed.snapshot?.holdings.allSatisfy { $0.imageURL == nil } == true)
        #expect(recovered.holdings.map(\.imageURL) == [nil, usdcLogo, nil])
        #expect(await http.logoRequests == [[usdcMint, usdtMint], [usdcMint, usdtMint]])
    }

    @Test(.timeLimit(.minutes(1)))
    func `A provider without logos shows none`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let logo = try #require(URL(string: "https://cdn.example.com/usdc.png"))
        let cached = Snapshot(owner: testWallet, network: .mainnet,
                              holdings: [.fixture(.fixture(usdcMint, decimals: 6), amount: 1, imageURL: logo)])
        try fixture.store.save(cached, for: CacheKey(owner: testWallet, network: .mainnet))
        let http = AccountResponses { _ in Ledger() }

        let refreshed = try #require(try await reload(fixture.portfolio(rpc: http.client)).snapshot)

        #expect(refreshed.holdings.allSatisfy { $0.imageURL == nil })
        #expect(await http.logoRequests.isEmpty)
    }

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
                             holdings: [.fixture(.fixture(usdcMint, decimals: 6), amount: 1, imageURL: logo)])
        try fixture.store.save(other, for: otherKey)

        try await service.providerDidChange()

        let original = try #require(read.snapshot)
        let saved = try #require(fixture.store.snapshot(for: CacheKey(owner: testWallet, network: .mainnet)))
        let otherSaved = try #require(fixture.store.snapshot(for: otherKey))
        #expect(saved.holdings.allSatisfy { $0.imageURL == nil })
        #expect(saved.holdings.map(\.balance) == original.holdings.map(\.balance))
        #expect(otherSaved.holdings.map(\.imageURL) == [nil])
        #expect(otherSaved.holdings.map(\.balance) == other.holdings.map(\.balance))
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

    @Test
    func `A provider change without saved snapshots succeeds`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let http = AccountResponses { _ in Ledger() }

        try await fixture.portfolio(rpc: http.client).providerDidChange()

        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path()))
    }

    @Test(.timeLimit(.minutes(1)))
    func `A provider change reports a snapshot whose logos can't be removed and still ends its work`() async throws {
        let fixture = Fixture()
        defer { fixture.removeFiles() }
        let cached = snapshot(owner: testWallet, network: .mainnet, amount: 3,
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

private struct Fixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var store: FileSnapshotStore { FileSnapshotStore(directory: directory) }
    var tokenLists: FileTokenListStore { FileTokenListStore(directory: directory.appendingPathComponent("TokenLists")) }

    func portfolio(rpc: any RPC, store: (any SnapshotStoring)? = nil) -> Portfolio {
        Portfolio(rpc: rpc, store: store ?? self.store, tokenLists: tokenLists)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: directory) }
}

private struct WriteFailingStore: SnapshotStoring {
    let cached: Snapshot?

    func snapshot(for key: CacheKey) -> Snapshot? { cached }

    func snapshots() -> [Snapshot] { cached.map { [$0] } ?? [] }

    func save(_ snapshot: Snapshot, for key: CacheKey) throws { throw CocoaError(.fileWriteOutOfSpace) }

    func remove(for key: CacheKey) throws { throw CocoaError(.fileWriteNoPermission) }
}

private func reload(_ service: Portfolio) async throws -> Update {
    var last: Update?
    for await update in await service.updates(for: testWallet) { last = update }
    return try #require(last)
}

private func snapshot(owner: String, network: Network, amount: UInt64, imageURL: URL? = nil) -> Snapshot {
    Snapshot(owner: owner, network: network,
             holdings: [.fixture(.fixture(usdcMint, decimals: 6), amount: amount, imageURL: imageURL)])
}
