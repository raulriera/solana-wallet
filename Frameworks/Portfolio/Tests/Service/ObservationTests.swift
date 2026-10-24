import Foundation
@testable import RPC
import Synchronization
import Testing
import Transactions
@testable import Portfolio

/// Exercises observation through real public-endpoint decoding with controlled HTTP and WebSocket transports.
struct ObservationTests {
    /// Verifies lagging balance responses preserve the last complete snapshot and report failure.
    /// - Parameter slot: A response slot older than the finalized change.
    @Test(.timeLimit(.minutes(1)), arguments: [100, 109] as [UInt64])
    func `Finalized changes reject older balance responses`(slot: UInt64) async throws {
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

        #expect(failed.error as? AccountReadError == .staleContext)
        #expect(failed.snapshot == original)
        #expect(fixture.store.snapshot(for: fixture.key) == original)
        #expect(await http.minimumSlots == [nil, 110])
        #expect(await ledger.readCount == 2)
        try await service.removeData(for: testWallet)
        await fixture.socket.waitUntilCancelled()
    }

    /// Verifies a finalized change replaces an older manual read while preserving both consumers.
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

    /// A price change reads an observed wallet's prices again and delivers them on the same stream.
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

    /// A price change starts a read in progress again, so its consumers never receive the previous prices.
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

    /// Verifies restarting subscriptions and receiving an older notification cannot lower the required slot.
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

        #expect(failed.error as? AccountReadError == .staleContext)
        #expect(failed.snapshot == current)
        #expect(fixture.store.snapshot(for: fixture.key) == current)
        #expect(await http.minimumSlots == [nil, 110, 110, 110])
        try await service.removeData(for: testWallet)
        await second.waitUntilCancelled()
    }

    /// Verifies a provider change closes the connection, drops the read in progress, and lets a new observation
    /// read balances from a provider that is behind the previous provider's newest finalized change.
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

    /// The ways a person changes an account's token list.
    enum ListChange: CaseIterable {
        /// Adding a token the list doesn't hold.
        case addition
        /// Removing a listed token.
        case removal
    }

    /// Verifies a new presentation reloads even when an existing consumer retains the connection.
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

    /// Verifies releasing the final stream stops observation even when its consumer exits normally.
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

    /// Verifies a finalized change bypasses fresh cache and reads balances after gathering nearby changes.
    /// - Parameter slot: A response slot at or beyond the finalized change.
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

    /// Verifies a change that arrives during a balance read leads to another read, so the latest balance shows.
    @Test(.timeLimit(.minutes(1)))
    func `A change during a balance read leads to another read`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let (pending, release) = AsyncStream<Void>.makeStream()
        let (started, announce) = AsyncStream<Void>.makeStream()
        defer { release.finish(); announce.finish() }
        let service = fixture.service { accounts in
            let reading = try await ledger.response(for: accounts)
            if await ledger.readCount == 2 {
                announce.yield(())
                for await _ in pending {}
            }
            return reading
        }
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

    /// Verifies observation watches the wallet and each listed token's associated account, as balance reads do.
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

    /// Verifies a list change moves an observed account's alerts to a new connection for the new list, then reads once.
    /// - Parameter change: How the token list changes.
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

    /// Verifies a removed token leaves every observer at once, before the account's balances are read again.
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

    /// Verifies a removal during a balance read starts the read again, so its consumers get the edited holdings first
    /// and the previous list's balances never arrive.
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

    /// Verifies list edits that change nothing keep the observed account's connection and read nothing.
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

    /// Verifies a failed request ends the cycle immediately instead of retrying.
    @Test(.timeLimit(.minutes(1)))
    func `Observation does not retry failed RPC requests`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let service = fixture.service(ledger: ledger)
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        let initial = try await nextResult(&updates)
        await ledger.fail()
        fixture.socket.notify(slot: 101)
        var delays = fixture.gate.delays.makeAsyncIterator()
        _ = try #require(await delays.next())
        fixture.gate.resume()
        let failed = try await nextResult(&updates)
        #expect(failed.error as? RPCError == .transport(.notConnectedToInternet))
        #expect(failed.snapshot == initial.snapshot)
        #expect(await ledger.readCount == 2)
        // A retry would first wait to gather changes; no such wait was requested.
        fixture.gate.finish()
        #expect(await delays.next() == nil)
        try await service.removeData(for: testWallet)
        await fixture.socket.waitUntilCancelled()
    }

    /// Verifies separate consumers share one connection and the last cancellation closes it.
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

    /// Verifies removing a wallet cancels a queued reload and prevents deleted data from returning.
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

    /// Verifies a dropped connection shows its error at once, keeps the stream, and reconnects to the same accounts.
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

    /// Verifies failed reconnections wait twice as long each time, up to a minute, and a working connection starts over.
    @Test(.timeLimit(.minutes(1)))
    func `Reconnection waits longer after each failed attempt`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        // No network and server errors both count as dropped connections.
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

    /// Verifies an acknowledged subscription whose balance read fails doesn't reset the reconnection wait.
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

    /// Verifies a rate limit or a rejected key stops reconnection but keeps the stream, and a reload connects again.
    /// - Parameter rejection: Why the provider refuses the subscription.
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

    /// Verifies adding a token to a stopped observation connects again for the new list and reads its balances.
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

    /// Verifies a new consumer connects a stopped observation again, as a second window does.
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

    /// Verifies a reload connects at once while a reconnection waits.
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
}

/// Holds the SOL balance that the next successful balance read reports, and records each read's accounts.
private actor ObservedLedger {
    private var lamports: UInt64 = 100
    private var slot: UInt64 = 100
    private var offline = false
    /// The accounts each balance read requested, in order.
    private(set) var reads: [[String]] = []
    /// The number of balance reads so far.
    var readCount: Int { reads.count }

    /// Updates the balance that later reads report.
    /// - Parameters:
    ///   - lamports: The wallet's SOL balance in lamports.
    ///   - slot: The slot of the updated balances.
    func set(lamports: UInt64, slot: UInt64 = 110) {
        self.lamports = lamports
        self.slot = slot
    }

    /// Makes subsequent reads fail instead of returning an outdated balance.
    func fail() { offline = true }

    /// Records a read and returns the balance at the moment it starts.
    /// - Parameter accounts: The accounts the read requests.
    /// - Returns: The ledger state for the fixture's balance read.
    /// - Throws: An offline error when configured to fail.
    func response(for accounts: [String]) throws -> Ledger {
        reads.append(accounts)
        if offline { throw URLError(.notConnectedToInternet) }
        return Ledger(slot: slot, lamports: lamports)
    }
}

/// Exposes scheduling boundaries without elapsed-time waits.
private struct PauseGate: Sendable {
    let delays: AsyncStream<Duration>
    private let scheduled: AsyncStream<Duration>.Continuation
    private let releases: AsyncStream<Void>
    private let release: AsyncStream<Void>.Continuation

    /// Creates a gate with explicit scheduling and release streams.
    init() {
        (delays, scheduled) = AsyncStream.makeStream()
        (releases, release) = AsyncStream.makeStream()
    }

    /// Records a requested delay and waits for explicit test release or task cancellation.
    /// - Parameter duration: The delay requested by the observation policy.
    /// - Throws: A cancellation error if the observation ends while waiting.
    func pause(_ duration: Duration) async throws {
        try Task.checkCancellation()
        scheduled.yield(duration)
        var iterator = releases.makeAsyncIterator()
        _ = await iterator.next()
        try Task.checkCancellation()
    }

    /// Releases one scheduled delay.
    func resume() { release.yield(()) }
    /// Ends test scheduling and releases any pending continuation.
    func finish() { scheduled.finish(); release.finish() }
}

/// A shared real-client fixture with isolated cache, socket, and scheduling.
private struct ObservationFixture: Sendable {
    let socket = SocketFixture()
    let gate = PauseGate()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let key = CacheKey(owner: testWallet, network: .mainnet)
    var store: FileSnapshotStore { FileSnapshotStore(directory: directory) }

    /// Composes a real public-endpoint client with controlled network boundaries and the production Portfolio.
    /// - Parameters:
    ///   - connect: Opens each subscription connection; `nil` reuses the fixture's socket.
    ///   - respond: The balance-read responder.
    /// - Returns: The portfolio service whose observation behavior is exercised.
    func service(connect: (@Sendable (URL) -> any WebSocketConnection)? = nil,
                 respond: @escaping AccountResponses.Responder) -> Portfolio {
        let http = AccountResponses(respond: respond)
        return service(http: http, connect: connect)
    }

    /// Composes the real client with a transport whose request options the test can inspect.
    /// - Parameters:
    ///   - http: The scripted account response transport.
    ///   - prices: The price provider, or `nil` for none.
    ///   - connect: Opens each subscription connection; `nil` reuses the fixture's socket.
    /// - Returns: The portfolio service whose observation behavior is exercised.
    func service(http: AccountResponses, prices: (any PriceProviding)? = nil,
                 connect: (@Sendable (URL) -> any WebSocketConnection)? = nil) -> Portfolio {
        let rpc = Solana(network: .mainnet, transport: http, socket: connect ?? { _ in socket })
        return Portfolio(rpc: rpc, store: store, tokenLists: isolatedTokenLists(), prices: prices,
                         pause: { try await gate.pause($0) })
    }

    /// Composes a service whose balance reads report the given ledger.
    /// - Parameters:
    ///   - ledger: The balance state.
    ///   - connect: Opens each subscription connection; `nil` reuses the fixture's socket.
    /// - Returns: The portfolio service whose observation behavior is exercised.
    func service(ledger: ObservedLedger, connect: (@Sendable (URL) -> any WebSocketConnection)? = nil) -> Portfolio {
        service(connect: connect) { try await ledger.response(for: $0) }
    }

    /// Ends fixture networking and removes only this test's cache files.
    func cleanUp() { socket.cancel(); gate.finish(); try? FileManager.default.removeItem(at: directory) }
}

/// Answers price lookups with SOL's current dollar price, which a test changes between lookups.
private final class SOLPrice: Sendable {
    private let state: Mutex<(dollars: Int, lookups: Int)>

    /// Starts at a price before any lookup.
    /// - Parameter dollars: SOL's price in dollars.
    init(dollars: Int) {
        state = Mutex((dollars, 0))
    }

    /// Changes the price that later lookups report.
    /// - Parameter dollars: SOL's new price in dollars.
    func set(dollars: Int) {
        state.withLock { $0.dollars = dollars }
    }

    /// Counts a lookup and answers it with the price at the moment it starts.
    /// - Returns: The price provider's response body, and how many lookups there have been, including this one.
    func lookUp() -> (body: Data, count: Int) {
        let (dollars, count) = state.withLock { state in
            state.lookups += 1
            return (state.dollars, state.lookups)
        }
        return (Data(#"{"\#(nativeMint)":{"usdPrice":\#(dollars)}}"#.utf8), count)
    }
}

/// Gives each subscription connection a new socket and hands it to the test, so tests can follow reconnections.
private final class Connections: Sendable {
    /// The sockets in the order the service opened them.
    let opened: AsyncStream<SocketFixture>
    private let announce: AsyncStream<SocketFixture>.Continuation
    private let rejection: @Sendable (Int) -> (any Error)?
    private let opens = Mutex(0)

    /// The number of connections the service opened.
    var count: Int { opens.withLock { $0 } }

    /// Creates a source of new sockets.
    /// - Parameter rejection: The error that refuses the subscriptions on the connection with this one-based number,
    ///   or `nil` to accept them.
    init(rejection: @escaping @Sendable (Int) -> (any Error)? = { _ in nil }) {
        (opened, announce) = AsyncStream.makeStream()
        self.rejection = rejection
    }

    /// Opens a new socket for one connection.
    /// - Parameter endpoint: The provider's WebSocket endpoint, which the fixture ignores.
    /// - Returns: A new scripted socket.
    func connect(to endpoint: URL) -> any WebSocketConnection {
        let number = opens.withLock { $0 += 1; return $0 }
        let socket = if let error = rejection(number) { SocketFixture { _, _ in throw error } } else { SocketFixture() }
        announce.yield(socket)
        return socket
    }
}

/// Reads through progress updates to one complete success or failure.
/// - Parameter iterator: The observation stream's active iterator.
/// - Returns: The next completed update, which callers waiting only for completion may ignore.
/// - Throws: A prerequisite error if observation ends before yielding a result.
@discardableResult
private func nextResult(_ iterator: inout AsyncStream<Update>.AsyncIterator) async throws -> Update {
    while let update = await iterator.next(isolation: #isolation) {
        if !update.isRefreshing { return update }
    }
    return try #require(nil as Update?)
}

/// Limits an observation stream's lifetime to one completed result.
/// - Parameter service: The portfolio whose observation to release on return.
/// - Returns: Its first completed update.
/// - Throws: A prerequisite error if the stream ends without a result.
private func firstObservation(from service: Portfolio) async throws -> Update {
    var iterator = await service.observations(for: testWallet).makeAsyncIterator()
    return try await nextResult(&iterator)
}
