import Foundation
import Synchronization
import Testing
import Transactions
@testable import Portfolio
@testable import RPC

struct ObservationTests {
    @Test(.timeLimit(.minutes(1)), arguments: [100, 109] as [UInt64])
    func `Finalized changes reject older balance responses and read again after a delay`(slot: UInt64) async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let http = AccountResponses { try await ledger.response(for: $0) }
        let service = fixture.service(http: http)
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        let initial = try await nextResult(&updates)
        let original = try #require(initial.snapshot)

        await ledger.set(lamports: 100, slot: slot)
        fixture.socket.notify(slot: 110)
        var delays = fixture.gate.delays.makeAsyncIterator()
        _ = try #require(await delays.next())
        fixture.gate.resume()
        let failed = try await nextResult(&updates)

        #expect(failed.error as? RPCError == .invalidResponse(.staleContext))
        #expect(failed.snapshot == original)
        #expect(fixture.store.snapshot(for: fixture.key) == original)
        #expect(await http.minimumSlots == [nil, 110])

        await ledger.set(lamports: 200, slot: 110)
        #expect(await delays.next() == .seconds(2))
        fixture.gate.resume()
        let retried = try await nextResult(&updates)

        #expect(retried.error == nil)
        #expect(retried.holdings.first?.amount?.units == 200)
        #expect(await http.minimumSlots == [nil, 110, 110])
        try await service.removeData(for: testWallet)
        await fixture.socket.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `A reload during a retry's wait reads at once`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let service = fixture.service(ledger: ledger)
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&updates)
        fixture.socket.notify(slot: 110)
        var delays = fixture.gate.delays.makeAsyncIterator()
        _ = try #require(await delays.next())
        fixture.gate.resume()
        try #require(try await nextResult(&updates).error as? RPCError == .invalidResponse(.staleContext))
        _ = try #require(await delays.next())

        await ledger.set(lamports: 200, slot: 110)
        await service.reload(for: testWallet)
        let reloaded = try await nextResult(&updates)

        #expect(reloaded.error == nil)
        #expect(reloaded.holdings.first?.amount?.units == 200)
        #expect(await ledger.readCount == 3)
        try await service.removeData(for: testWallet)
        await fixture.socket.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `A change's pending read still runs after the connection is refused`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let service = fixture.service(ledger: ledger)
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&updates)
        await ledger.set(lamports: 200)
        fixture.socket.notify(slot: 110)
        var delays = fixture.gate.delays.makeAsyncIterator()
        _ = try #require(await delays.next())
        fixture.socket.fail(RPCError.http(statusCode: 401, retryAfter: nil))
        try #require(try await nextResult(&updates).error as? RPCError == .http(statusCode: 401, retryAfter: nil))

        fixture.gate.resume()
        let read = try await nextResult(&updates)

        #expect(read.error == nil)
        #expect(read.holdings.first?.amount?.units == 200)
        try await service.removeData(for: testWallet)
    }

    @Test(.timeLimit(.minutes(1)))
    func `A finalized change replaces an active manual read with a newer read`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, announce) = AsyncStream<Void>.makeStream()
        defer { release.finish(); announce.finish() }
        let http = AccountResponses { accounts in
            let reading = try await ledger.response(for: accounts)
            if await ledger.readCount == 2 {
                announce.yield(())
                for await _ in pending {}
            }
            return reading
        }
        let service = fixture.service(http: http)
        var observed = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&observed)

        await ledger.set(lamports: 200, slot: 100)
        var manual = await service.updates(for: testWallet).makeAsyncIterator()
        _ = try #require(await manual.next())
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())

        await ledger.set(lamports: 300, slot: 110)
        fixture.socket.notify(slot: 110)
        var delays = fixture.gate.delays.makeAsyncIterator()
        _ = try #require(await delays.next())
        fixture.gate.resume()
        let joined = try #require(await observed.next())
        try #require(joined.isRefreshing)
        release.finish()

        let manualResult = try await nextResult(&manual)
        let observedResult = try await nextResult(&observed)
        #expect(manualResult.error == nil)
        #expect(observedResult.error == nil)
        #expect(manualResult.holdings.first?.amount?.units == 300)
        #expect(observedResult.snapshot == manualResult.snapshot)
        #expect(fixture.store.snapshot(for: fixture.key) == manualResult.snapshot)
        #expect(await http.minimumSlots == [nil, nil, 110])
        #expect(await manual.next() == nil)
        try await service.removeData(for: testWallet)
        await fixture.socket.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `A price change reads an observed wallet's prices again`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let price = SOLPrice(dollars: 100)
        let prices = PriceResponses { _ in price.lookUp().body }
        let connections = Connections()
        let service = fixture.service(http: AccountResponses { try await ledger.response(for: $0) },
                                      prices: prices.client) { connections.connect(to: $0) }
        var sockets = connections.opened.makeAsyncIterator()
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        let initial = try await nextResult(&updates)
        let first = try #require(await sockets.next())
        #expect(initial.holdings.first?.valuation?.pricePerUnit == 100)

        price.set(dollars: 200)
        await service.pricesDidChange()

        let repriced = try await nextResult(&updates)
        #expect(repriced.error == nil)
        #expect(repriced.holdings.first?.valuation?.pricePerUnit == 200)
        #expect(await ledger.readCount == 2)
        await first.waitUntilCancelled()
        let second = try #require(await sockets.next())
        try await service.removeData(for: testWallet)
        await second.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `A price change restarts a read in progress`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, announce) = AsyncStream<Void>.makeStream()
        defer { release.finish(); announce.finish() }
        let price = SOLPrice(dollars: 100)
        let prices = PriceResponses { _ in
            let lookup = price.lookUp()
            if lookup.count == 1 {
                announce.yield(())
                for await _ in pending {}
            }
            return lookup.body
        }
        let connections = Connections()
        let service = fixture.service(http: AccountResponses { _ in Ledger(slot: 100, lamports: 100) },
                                      prices: prices.client) { connections.connect(to: $0) }
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())

        price.set(dollars: 200)
        await service.pricesDidChange()

        let repriced = try await nextResult(&updates)
        #expect(repriced.error == nil)
        #expect(repriced.holdings.first?.valuation?.pricePerUnit == 200)
        try await service.removeData(for: testWallet)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Token list changes preserve the newest finalized slot across connections`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let http = AccountResponses { try await ledger.response(for: $0) }
        let connections = Connections()
        let service = fixture.service(http: http) { connections.connect(to: $0) }
        var sockets = connections.opened.makeAsyncIterator()
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&updates)
        let first = try #require(await sockets.next())

        await ledger.set(lamports: 200, slot: 110)
        first.notify(slot: 110)
        var delays = fixture.gate.delays.makeAsyncIterator()
        _ = try #require(await delays.next())
        fixture.gate.resume()
        try await nextResult(&updates)

        try await service.removeToken(Address(usdcMint), for: testWallet)
        await first.waitUntilCancelled()
        let second = try #require(await sockets.next())
        let changed = try await nextResult(&updates)
        let current = try #require(changed.snapshot)
        try #require(changed.error == nil)
        #expect(changed.holdings.map(\.id) == [.nativeSOL, .asset(usdtMint)])
        #expect(await http.minimumSlots == [nil, 110, 110])

        await ledger.set(lamports: 300, slot: 109)
        second.notify(slot: 109)
        _ = try #require(await delays.next())
        fixture.gate.resume()
        let failed = try await nextResult(&updates)

        #expect(failed.error as? RPCError == .invalidResponse(.staleContext))
        #expect(failed.snapshot == current)
        #expect(fixture.store.snapshot(for: fixture.key) == current)
        #expect(await http.minimumSlots == [nil, 110, 110, 110])
        try await service.removeData(for: testWallet)
        await second.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `A provider change ends observation and the next one needs no earlier finalized slot`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, announce) = AsyncStream<Void>.makeStream()
        defer { release.finish(); announce.finish() }
        let http = AccountResponses { accounts in
            let reading = try await ledger.response(for: accounts)
            if await ledger.readCount == 2 {
                announce.yield(())
                for await _ in pending {}
            }
            return reading
        }
        let connections = Connections()
        let service = fixture.service(http: http) { connections.connect(to: $0) }
        var sockets = connections.opened.makeAsyncIterator()
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&updates)
        let first = try #require(await sockets.next())
        await ledger.set(lamports: 200, slot: 110)
        first.notify(slot: 110)
        var delays = fixture.gate.delays.makeAsyncIterator()
        _ = try #require(await delays.next())
        fixture.gate.resume()
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())

        try await service.providerDidChange()

        while let update = await updates.next() { #expect(update.isRefreshing) }
        await first.waitUntilCancelled()
        await ledger.set(lamports: 300, slot: 100)
        release.finish()
        var observed = await service.observations(for: testWallet).makeAsyncIterator()
        let second = try #require(await sockets.next())
        let result = try await nextResult(&observed)
        #expect(result.error == nil)
        #expect(result.holdings.first?.amount?.units == 300)
        #expect(fixture.store.snapshot(for: fixture.key) == result.snapshot)
        #expect(await http.minimumSlots == [nil, 110, nil])
        try await service.removeData(for: testWallet)
        await second.waitUntilCancelled()
    }

    enum ListChange: CaseIterable {
        case addition
        case removal
    }

    @Test(.timeLimit(.minutes(1)))
    func `Joining an established observation reloads fresh cached holdings`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let service = fixture.service(ledger: ledger)
        var first = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&first)
        await ledger.set(lamports: 200)

        var joined = await service.observations(for: testWallet).makeAsyncIterator()
        let initial = try #require(await joined.next())
        try #require(initial.isRefreshing)
        let refreshed = try await nextResult(&joined)
        #expect(refreshed.holdings.first?.amount?.units == 200)
        #expect(await ledger.readCount == 2)
        #expect(fixture.socket.requests.count == 3)
        try await service.removeData(for: testWallet)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Leaving portfolio observation scope closes its connection`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let service = fixture.service(ledger: ObservedLedger())
        let initial = try await firstObservation(from: service)
        #expect(initial.error == nil)
        await fixture.socket.waitUntilCancelled()
        #expect(fixture.store.snapshot(for: fixture.key) == initial.snapshot)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [110, 120] as [UInt64])
    func `Finalized changes refresh fresh portfolios`(slot: UInt64) async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let http = AccountResponses { try await ledger.response(for: $0) }
        let service = fixture.service(http: http)
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        let initial = try await nextResult(&updates)
        let original = try #require(initial.snapshot)
        #expect(fixture.socket.requests.count == 3)

        await ledger.set(lamports: 200, slot: slot)
        fixture.socket.notify(slot: 110, subscription: 3)
        var delays = fixture.gate.delays.makeAsyncIterator()
        #expect(await delays.next() == .seconds(2))
        #expect(fixture.store.snapshot(for: fixture.key) == original)
        fixture.gate.resume()
        let updated = try await nextResult(&updates)
        #expect(updated.error == nil)
        #expect(updated.holdings.first?.amount?.units == 200)
        #expect(fixture.store.snapshot(for: fixture.key) == updated.snapshot)
        #expect(await http.minimumSlots == [nil, 110])
        #expect(await ledger.readCount == 2)
        try await service.removeData(for: testWallet)
        await fixture.socket.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)), arguments: [200, 429])
    func `A change during a balance read leads to another read even when prices fail`(priceStatus: Int) async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, announce) = AsyncStream<Void>.makeStream()
        defer { release.finish(); announce.finish() }
        let prices = PriceResponses(status: priceStatus) { _ in Data("{}".utf8) }
        let http = AccountResponses { accounts in
            let reading = try await ledger.response(for: accounts)
            if await ledger.readCount == 2 {
                announce.yield(())
                for await _ in pending {}
            }
            return reading
        }
        let service = fixture.service(http: http, prices: prices.client)
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&updates)
        await ledger.set(lamports: 200)
        fixture.socket.notify(slot: 101)
        var delays = fixture.gate.delays.makeAsyncIterator()
        #expect(await delays.next() == .seconds(2))
        fixture.gate.resume()
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())

        await ledger.set(lamports: 300)
        fixture.socket.notify(slot: 102)
        release.finish()

        let earlier = try await nextResult(&updates)
        #expect(earlier.holdings.first?.amount?.units == 200)
        #expect(await delays.next() == .seconds(2))
        fixture.gate.resume()
        let latest = try await nextResult(&updates)
        #expect(latest.holdings.first?.amount?.units == 300)
        #expect(fixture.store.snapshot(for: fixture.key) == latest.snapshot)
        #expect(await ledger.readCount == 3)
        try await service.removeData(for: testWallet)
        await fixture.socket.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `Observation watches the wallet and each listed token account`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let service = fixture.service(ledger: ledger)
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&updates)

        let wallet = try Address(testWallet)
        let tokenAccounts = try [usdcMint, usdtMint].map {
            try TokenProgram.token.associatedAccount(owner: wallet, mint: Address($0)).value
        }
        #expect(fixture.socket.subscribedAddresses == [testWallet] + tokenAccounts)
        #expect(await ledger.reads == [[testWallet] + tokenAccounts])
        try await service.removeData(for: testWallet)
        await fixture.socket.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)), arguments: ListChange.allCases)
    func `Changing an observed token list watches the new list and reads balances once`(_ change: ListChange) async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let connections = Connections()
        let service = fixture.service(ledger: ledger) { connections.connect(to: $0) }
        var sockets = connections.opened.makeAsyncIterator()
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&updates)
        let first = try #require(await sockets.next())

        let expected: [Holding.Identity]
        switch change {
        case .addition:
            try await service.addToken(ListedToken(mint: Address(pyusdMint), program: .token2022, decimals: 6,
                                                   symbol: "PYUSD", name: "PayPal USD"), for: testWallet)
            expected = [.nativeSOL, .asset(usdcMint), .asset(usdtMint), .asset(pyusdMint)]
        case .removal:
            try await service.removeToken(Address(usdcMint), for: testWallet)
            expected = [.nativeSOL, .asset(usdtMint)]
        }
        await first.waitUntilCancelled()
        let second = try #require(await sockets.next())
        let changed = try await nextResult(&updates)

        #expect(changed.error == nil)
        #expect(changed.holdings.map(\.id) == expected)
        let reads = await ledger.reads
        #expect(reads.count == 2)
        #expect(second.subscribedAddresses == reads.last)
        try await service.removeData(for: testWallet)
        await second.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `A removed token leaves an observed account before the next balance read`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let connections = Connections()
        let service = fixture.service(ledger: ObservedLedger()) { connections.connect(to: $0) }
        var sockets = connections.opened.makeAsyncIterator()
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        let initial = try await nextResult(&updates)
        let first = try #require(await sockets.next())

        try await service.removeToken(Address(usdcMint), for: testWallet)
        let removed = try #require(await updates.next())

        let remaining = initial.holdings.map(\.id).filter { $0 != .asset(usdcMint) }
        #expect(removed.isRefreshing)
        #expect(removed.holdings.map(\.id) == remaining)
        #expect(removed.snapshotRevision.map { $0 > initial.snapshotRevision ?? 0 } == true)
        #expect(fixture.store.snapshot(for: fixture.key)?.holdings.map(\.id) == remaining)
        await first.waitUntilCancelled()
        let second = try #require(await sockets.next())
        try await service.removeData(for: testWallet)
        await second.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `A removal during a balance read replaces the read of the previous list`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, announce) = AsyncStream<Void>.makeStream()
        defer { release.finish(); announce.finish() }
        let http = AccountResponses { accounts in
            let reading = try await ledger.response(for: accounts)
            if await ledger.readCount == 2 {
                announce.yield(())
                for await _ in pending {}
            }
            return reading
        }
        let service = fixture.service(http: http)
        var first = await service.updates(for: testWallet).makeAsyncIterator()
        let cached = try await nextResult(&first)
        var reload = await service.updates(for: testWallet).makeAsyncIterator()
        _ = try #require(await reload.next())
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())

        try await service.removeToken(Address(usdcMint), for: testWallet)
        let edited = try #require(await reload.next())
        release.finish()
        let result = try await nextResult(&reload)

        let remaining = cached.holdings.map(\.id).filter { $0 != .asset(usdcMint) }
        #expect(edited.isRefreshing)
        #expect(edited.holdings.map(\.id) == remaining)
        #expect(result.error == nil)
        #expect(result.holdings.map(\.id) == remaining)
        #expect(fixture.store.snapshot(for: fixture.key)?.holdings.map(\.id) == remaining)
        #expect(await reload.next() == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Token list edits that change nothing keep the observation`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let service = fixture.service(ledger: ledger)
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&updates)

        let usdc = try #require(try TokenList(defaultsFor: .mainnet).tokens.first)
        try await service.addToken(usdc, for: testWallet)
        try await service.removeToken(Address(pyusdMint), for: testWallet)
        await ledger.set(lamports: 200)
        fixture.socket.notify(slot: 101)
        var delays = fixture.gate.delays.makeAsyncIterator()
        _ = try #require(await delays.next())
        fixture.gate.resume()
        let updated = try await nextResult(&updates)

        #expect(updated.holdings.first?.amount?.units == 200)
        #expect(await ledger.readCount == 2)
        #expect(fixture.socket.requests.count == 3)
        try await service.removeData(for: testWallet)
        await fixture.socket.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `Observation does not retry refused RPC requests`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let service = fixture.service(ledger: ledger)
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        let initial = try await nextResult(&updates)
        await ledger.fail(with: RPCError.http(statusCode: 401, retryAfter: nil))
        fixture.socket.notify(slot: 101)
        var delays = fixture.gate.delays.makeAsyncIterator()
        _ = try #require(await delays.next())
        fixture.gate.resume()
        let failed = try await nextResult(&updates)
        #expect(failed.error as? RPCError == .http(statusCode: 401, retryAfter: nil))
        #expect(failed.snapshot == initial.snapshot)
        #expect(await ledger.readCount == 2)
        fixture.gate.finish()
        #expect(await delays.next() == nil)
        try await service.removeData(for: testWallet)
        await fixture.socket.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `Portfolio observers share a connection until the final consumer leaves`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let service = fixture.service(ledger: ledger)
        let first = await service.observations(for: testWallet)
        let second = await service.observations(for: testWallet)
        let (ready, announce) = AsyncStream<Void>.makeStream()
        defer { announce.finish() }
        let consumer = Task {
            for await update in first where !update.isRefreshing { announce.yield(()) }
        }
        defer { consumer.cancel() }
        var delivered = ready.makeAsyncIterator()
        _ = try #require(await delivered.next())
        consumer.cancel()
        await consumer.value
        var remaining = second.makeAsyncIterator()
        try await nextResult(&remaining)
        #expect(!fixture.socket.isCancelled)
        #expect(fixture.socket.requests.count == 3)
        #expect(await ledger.readCount == 1)

        let last = Task { for await _ in second {} }
        last.cancel()
        await last.value
        await fixture.socket.waitUntilCancelled()
        #expect(fixture.store.snapshot(for: fixture.key) != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Removing a watched wallet cancels queued reconciliation`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let service = fixture.service(ledger: ledger)
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&updates)
        fixture.socket.notify(slot: 101)
        var delays = fixture.gate.delays.makeAsyncIterator()
        _ = try #require(await delays.next())
        try await service.removeData(for: testWallet)
        await fixture.socket.waitUntilCancelled()
        #expect(await updates.next() == nil)
        #expect(fixture.store.snapshot(for: fixture.key) == nil)
        #expect(await ledger.readCount == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func `A dropped connection reconnects and reads balances again`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let connections = Connections()
        let service = fixture.service(ledger: ledger) { connections.connect(to: $0) }
        var sockets = connections.opened.makeAsyncIterator()
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        let original = try await nextResult(&updates)
        let first = try #require(await sockets.next())

        first.fail(URLError(.networkConnectionLost))
        let failed = try await nextResult(&updates)
        #expect(failed.error as? RPCError == .transport(.networkConnectionLost))
        #expect(failed.snapshot == original.snapshot)
        var delays = fixture.gate.delays.makeAsyncIterator()
        #expect(await delays.next() == .seconds(2))
        await ledger.set(lamports: 200)
        fixture.gate.resume()
        let second = try #require(await sockets.next())
        let reconnected = try await nextResult(&updates)

        #expect(reconnected.error == nil)
        #expect(reconnected.holdings.first?.amount?.units == 200)
        #expect(second.subscribedAddresses == first.subscribedAddresses)
        #expect(await ledger.readCount == 2)
        try await service.removeData(for: testWallet)
        await second.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `Reconnection waits longer after each failed attempt`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let connections = Connections { number in
            guard (2...9).contains(number) else { return nil }
            let offline: any Error = URLError(.notConnectedToInternet)
            return number.isMultiple(of: 2) ? offline : RPCError.http(statusCode: 503, retryAfter: nil)
        }
        let service = fixture.service(ledger: ObservedLedger()) { connections.connect(to: $0) }
        var sockets = connections.opened.makeAsyncIterator()
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&updates)
        var latest = try #require(await sockets.next())

        latest.fail(URLError(.networkConnectionLost))
        var delays = fixture.gate.delays.makeAsyncIterator()
        var waited: [Duration] = []
        for _ in 2...10 {
            waited.append(try #require(await delays.next()))
            fixture.gate.resume()
            latest = try #require(await sockets.next())
        }
        #expect(waited == [2, 4, 8, 16, 32, 60, 60, 60, 60].map(Duration.seconds))

        while try await nextResult(&updates).error != nil {}
        latest.fail(URLError(.networkConnectionLost))
        #expect(await delays.next() == .seconds(2))
        fixture.gate.resume()
        let reconnected = try #require(await sockets.next())
        try await service.removeData(for: testWallet)
        await reconnected.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `A connection whose balance read fails keeps waiting longer`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let connections = Connections()
        let service = fixture.service(ledger: ledger) { connections.connect(to: $0) }
        var sockets = connections.opened.makeAsyncIterator()
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&updates)
        let first = try #require(await sockets.next())

        await ledger.fail()
        first.fail(URLError(.networkConnectionLost))
        #expect(try await nextResult(&updates).error as? RPCError == .transport(.networkConnectionLost))
        var delays = fixture.gate.delays.makeAsyncIterator()
        #expect(await delays.next() == .seconds(2))
        fixture.gate.resume()
        let second = try #require(await sockets.next())
        #expect(try await nextResult(&updates).error as? RPCError == .transport(.notConnectedToInternet))
        second.fail(URLError(.networkConnectionLost))

        #expect(await delays.next() == .seconds(4))
        try await service.removeData(for: testWallet)
    }

    @Test(.timeLimit(.minutes(1)),
          arguments: [RPCError.http(statusCode: 429, retryAfter: nil), RPCError.http(statusCode: 401, retryAfter: nil)])
    func `A refused subscription waits for a reload to connect again`(rejection: RPCError) async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let connections = Connections { $0 == 1 ? rejection : nil }
        let service = fixture.service(ledger: ledger) { connections.connect(to: $0) }
        var sockets = connections.opened.makeAsyncIterator()
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        let refused = try await nextResult(&updates)
        _ = try #require(await sockets.next())
        #expect(refused.error as? RPCError == rejection)

        await ledger.set(lamports: 200)
        var manual = await service.updates(for: testWallet).makeAsyncIterator()
        let second = try #require(await sockets.next())
        let reloaded = try await nextResult(&manual)
        let observed = try await nextResult(&updates)

        #expect(reloaded.holdings.first?.amount?.units == 200)
        #expect(observed.error == nil)
        #expect(observed.holdings.first?.amount?.units == 200)
        fixture.gate.finish()
        var waited: [Duration] = []
        for await delay in fixture.gate.delays { waited.append(delay) }
        #expect(waited.isEmpty)
        try await service.removeData(for: testWallet)
        await second.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `Adding a token connects a stopped observation again`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let connections = Connections { $0 == 1 ? RPCError.http(statusCode: 429, retryAfter: nil) : nil }
        let service = fixture.service(ledger: ledger) { connections.connect(to: $0) }
        var sockets = connections.opened.makeAsyncIterator()
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&updates)
        _ = try #require(await sockets.next())

        try await service.addToken(ListedToken(mint: Address(pyusdMint), program: .token2022, decimals: 6,
                                               symbol: "PYUSD", name: "PayPal USD"), for: testWallet)
        let second = try #require(await sockets.next())
        let changed = try await nextResult(&updates)

        #expect(changed.error == nil)
        #expect(changed.holdings.map(\.id) == [.nativeSOL, .asset(usdcMint), .asset(usdtMint), .asset(pyusdMint)])
        #expect(await ledger.reads == [second.subscribedAddresses])
        try await service.removeData(for: testWallet)
        await second.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `Joining a stopped observation connects again`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let connections = Connections { $0 == 1 ? RPCError.http(statusCode: 429, retryAfter: nil) : nil }
        let service = fixture.service(ledger: ObservedLedger()) { connections.connect(to: $0) }
        var sockets = connections.opened.makeAsyncIterator()
        var first = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&first)
        _ = try #require(await sockets.next())

        var joined = await service.observations(for: testWallet).makeAsyncIterator()
        let second = try #require(await sockets.next())
        let joinedResult = try await nextResult(&joined)
        let firstResult = try await nextResult(&first)

        #expect(joinedResult.error == nil)
        #expect(firstResult.error == nil)
        try await service.removeData(for: testWallet)
        await second.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `A reload connects at once while the reconnection waits`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let connections = Connections()
        let service = fixture.service(ledger: ledger) { connections.connect(to: $0) }
        var sockets = connections.opened.makeAsyncIterator()
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&updates)
        let first = try #require(await sockets.next())
        first.fail(URLError(.notConnectedToInternet))
        try await nextResult(&updates)
        var delays = fixture.gate.delays.makeAsyncIterator()
        _ = try #require(await delays.next())

        await ledger.set(lamports: 200)
        var manual = await service.updates(for: testWallet).makeAsyncIterator()
        let second = try #require(await sockets.next())
        try await nextResult(&manual)
        let observed = try await nextResult(&updates)

        #expect(observed.error == nil)
        #expect(observed.holdings.first?.amount?.units == 200)
        try await service.removeData(for: testWallet)
        await second.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `A reload reads an observed wallet again for every consumer`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let service = fixture.service(ledger: ledger)
        var first = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&first)
        var second = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&second)
        try await nextResult(&first)
        await ledger.set(lamports: 200)

        await service.reload(for: testWallet)

        #expect(try await nextResult(&first).holdings.first?.amount?.units == 200)
        #expect(try await nextResult(&second).holdings.first?.amount?.units == 200)
        #expect(await ledger.readCount == 3)
        try await service.removeData(for: testWallet)
        await fixture.socket.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `Cancelling a reload ends its wait and keeps its read`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, announce) = AsyncStream<Void>.makeStream()
        defer {
            release.finish()
            announce.finish()
        }
        let http = AccountResponses { accounts in
            let reading = try await ledger.response(for: accounts)
            if await ledger.readCount == 2 {
                announce.yield(())
                for await _ in pending {}
            }
            return reading
        }
        let service = fixture.service(http: http)
        var observed = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&observed)
        await ledger.set(lamports: 200)
        let reloading = Task { await service.reload(for: testWallet) }
        var startedIterator = started.makeAsyncIterator()
        _ = try #require(await startedIterator.next())

        reloading.cancel()
        await reloading.value
        release.finish()

        #expect(try await nextResult(&observed).holdings.first?.amount?.units == 200)
        #expect(await ledger.readCount == 2)
        try await service.removeData(for: testWallet)
        await fixture.socket.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `A reload connects a refused observation again`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let connections = Connections { $0 == 1 ? RPCError.http(statusCode: 429, retryAfter: nil) : nil }
        let service = fixture.service(ledger: ledger) { connections.connect(to: $0) }
        var sockets = connections.opened.makeAsyncIterator()
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        try await nextResult(&updates)
        _ = try #require(await sockets.next())
        await ledger.set(lamports: 200)

        await service.reload(for: testWallet)

        let second = try #require(await sockets.next())
        let reloaded = try await nextResult(&updates)
        #expect(reloaded.error == nil)
        #expect(reloaded.holdings.first?.amount?.units == 200)
        try await service.removeData(for: testWallet)
        await second.waitUntilCancelled()
    }

    @Test(.timeLimit(.minutes(1)))
    func `A reload of a wallet that isn't observed reads nothing`() async {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let service = fixture.service(ledger: ledger)

        await service.reload(for: testWallet)

        #expect(await ledger.readCount == 0)
    }
}

private actor ObservedLedger {
    private var lamports: UInt64 = 100
    private var slot: UInt64 = 100
    private var error: (any Error)?
    private(set) var reads: [[String]] = []
    var readCount: Int { reads.count }

    func set(lamports: UInt64, slot: UInt64 = 110) {
        self.lamports = lamports
        self.slot = slot
    }

    func fail(with error: any Error = URLError(.notConnectedToInternet)) { self.error = error }

    func response(for accounts: [String]) throws -> Ledger {
        reads.append(accounts)
        if let error { throw error }
        return Ledger(slot: slot, lamports: lamports)
    }
}

private struct PauseGate: Clock, Sendable {
    let now = ContinuousClock.now
    let minimumResolution = Duration.nanoseconds(1)
    let delays: AsyncStream<Duration>
    private let scheduled: AsyncStream<Duration>.Continuation
    private let releases: AsyncStream<Void>
    private let release: AsyncStream<Void>.Continuation

    init() {
        (delays, scheduled) = AsyncStream.makeStream()
        (releases, release) = AsyncStream.makeStream()
    }

    func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {
        try await pause(now.duration(to: deadline))
    }

    func pause(_ duration: Duration) async throws {
        try Task.checkCancellation()
        scheduled.yield(duration)
        var iterator = releases.makeAsyncIterator()
        _ = await iterator.next()
        try Task.checkCancellation()
    }

    func resume() { release.yield(()) }
    func finish() { scheduled.finish(); release.finish() }
}

private struct ObservationFixture: Sendable {
    let socket = SocketFixture()
    let gate = PauseGate()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let key = CacheKey(owner: testWallet, network: .mainnet)
    var store: FileSnapshotStore { FileSnapshotStore(directory: directory) }

    func service(connect: (@Sendable (URL) -> any WebSocketConnection)? = nil,
                 respond: @escaping AccountResponses.Responder) -> Portfolio {
        let http = AccountResponses(respond: respond)
        return service(http: http, connect: connect)
    }

    func service(http: AccountResponses, prices: (any PriceProviding)? = nil,
                 connect: (@Sendable (URL) -> any WebSocketConnection)? = nil) -> Portfolio {
        let rpc = SolanaRPC(network: .mainnet, transport: http, socket: connect ?? { _ in socket })
        return Portfolio(rpc: rpc, store: store, tokenLists: isolatedTokenLists(), prices: prices,
                         clock: gate)
    }

    func service(ledger: ObservedLedger, connect: (@Sendable (URL) -> any WebSocketConnection)? = nil) -> Portfolio {
        service(connect: connect) { try await ledger.response(for: $0) }
    }

    func cleanUp() { socket.cancel(); gate.finish(); try? FileManager.default.removeItem(at: directory) }
}

private final class SOLPrice: Sendable {
    private let state: Mutex<(dollars: Int, lookups: Int)>

    init(dollars: Int) {
        state = Mutex((dollars, 0))
    }

    func set(dollars: Int) {
        state.withLock { $0.dollars = dollars }
    }

    func lookUp() -> (body: Data, count: Int) {
        let (dollars, count) = state.withLock { state in
            state.lookups += 1
            return (state.dollars, state.lookups)
        }
        return (Data(#"{"\#(nativeMint)":{"usdPrice":\#(dollars)}}"#.utf8), count)
    }
}

private final class Connections: Sendable {
    let opened: AsyncStream<SocketFixture>
    private let announce: AsyncStream<SocketFixture>.Continuation
    private let rejection: @Sendable (Int) -> (any Error)?
    private let opens = Mutex(0)

    var count: Int { opens.withLock { $0 } }

    init(rejection: @escaping @Sendable (Int) -> (any Error)? = { _ in nil }) {
        (opened, announce) = AsyncStream.makeStream()
        self.rejection = rejection
    }

    func connect(to endpoint: URL) -> any WebSocketConnection {
        let number = opens.withLock { $0 += 1; return $0 }
        let socket = if let error = rejection(number) { SocketFixture { _, _ in throw error } } else { SocketFixture() }
        announce.yield(socket)
        return socket
    }
}

@discardableResult
private func nextResult(_ iterator: inout AsyncStream<Update>.AsyncIterator) async throws -> Update {
    while let update = await iterator.next(isolation: #isolation) {
        if !update.isRefreshing { return update }
    }
    return try #require(nil as Update?)
}

private func firstObservation(from service: Portfolio) async throws -> Update {
    var iterator = await service.observations(for: testWallet).makeAsyncIterator()
    return try await nextResult(&iterator)
}
