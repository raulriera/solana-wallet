import Foundation
@testable import RPC
import Testing
@testable import Portfolio

/// Exercises observation through real public-endpoint decoding with controlled HTTP and WebSocket transports.
struct ObservationTests {
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

    /// Verifies a confirmed change bypasses fresh cache and reads balances after gathering nearby changes.
    @Test(.timeLimit(.minutes(1)))
    func `Confirmed changes refresh fresh portfolios`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let ledger = ObservedLedger()
        let service = fixture.service(ledger: ledger)
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        let initial = try await nextResult(&updates)
        let original = try #require(initial.snapshot)
        #expect(fixture.socket.requests.count == 3)

        await ledger.set(lamports: 200)
        fixture.socket.notify(slot: 110, subscription: 3, method: "programNotification")
        var delays = fixture.gate.delays.makeAsyncIterator()
        #expect(await delays.next() == .seconds(2))
        #expect(fixture.store.snapshot(for: fixture.key) == original)
        fixture.gate.resume()
        let updated = try await nextResult(&updates)
        #expect(updated.error == nil)
        #expect(updated.holdings.first?.amount?.units == 200)
        #expect(fixture.store.snapshot(for: fixture.key) == updated.snapshot)
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
        let service = fixture.service { _ in
            let reading = try await ledger.response()
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

    /// Verifies socket errors are visible, retain holdings, and end the watch without reconnecting.
    @Test(.timeLimit(.minutes(1)))
    func `Subscription failure ends portfolio observation with cached holdings`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let service = fixture.service(ledger: ObservedLedger())
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        let original = try await nextResult(&updates)
        fixture.socket.fail(URLError(.networkConnectionLost))
        let failed = try await nextResult(&updates)
        #expect(failed.error as? RPCError == .transport(.networkConnectionLost))
        #expect(failed.snapshot == original.snapshot)
        #expect(await updates.next() == nil)
        #expect(fixture.socket.requests.count == 3)
    }

    /// Verifies subscriptions cannot invalidate holdings on another network.
    @Test
    func `Observation rejects mismatched networks before connecting`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let accounts = AccountResponses { _ in throw URLError(.notConnectedToInternet) }
        let changes = Solana(network: .devnet, transport: accounts, socket: { _ in fixture.socket })
        let service = Portfolio(rpc: accounts.client, store: fixture.store, tokenLists: isolatedTokenLists(),
                                changes: changes)
        var updates = await service.observations(for: testWallet).makeAsyncIterator()
        let failed = try await nextResult(&updates)
        #expect(failed.error as? ObservationError == .networkMismatch)
        #expect(await updates.next() == nil)
        #expect(fixture.socket.requests.isEmpty)
        #expect(await accounts.requests.isEmpty)
    }
}

/// Holds the SOL balance that the next successful balance read reports.
private actor ObservedLedger {
    private var lamports: UInt64 = 100
    private var offline = false
    private(set) var readCount = 0

    /// Updates the balance that later reads report.
    /// - Parameter lamports: The wallet's SOL balance in lamports.
    func set(lamports: UInt64) { self.lamports = lamports }

    /// Makes subsequent reads fail instead of returning an outdated balance.
    func fail() { offline = true }

    /// Counts a read and returns the balance at the moment it starts.
    /// - Returns: The ledger state for the fixture's balance read.
    /// - Throws: An offline error when configured to fail.
    func response() throws -> Ledger {
        readCount += 1
        if offline { throw URLError(.notConnectedToInternet) }
        return Ledger(lamports: lamports)
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
    /// - Parameter respond: The balance-read responder.
    /// - Returns: The portfolio service whose observation behavior is exercised.
    func service(respond: @escaping AccountResponses.Responder) -> Portfolio {
        let http = AccountResponses(respond: respond)
        let rpc = Solana(network: .mainnet, transport: http, socket: { _ in socket })
        return Portfolio(rpc: rpc, store: store, tokenLists: isolatedTokenLists(), pause: { try await gate.pause($0) })
    }

    /// Composes a service whose balance reads report the given ledger.
    /// - Parameter ledger: The balance state.
    /// - Returns: The portfolio service whose observation behavior is exercised.
    func service(ledger: ObservedLedger) -> Portfolio {
        service { _ in try await ledger.response() }
    }

    /// Ends fixture networking and removes only this test's cache files.
    func cleanUp() { socket.cancel(); gate.finish(); try? FileManager.default.removeItem(at: directory) }
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
