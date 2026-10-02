import Foundation
@testable import RPC
import Testing
@testable import Portfolio

/// Exercises observation through real Helius decoding with controlled HTTP and WebSocket transports.
struct ObservationTests {
    /// Verifies a new presentation reloads even when an existing consumer retains the connection.
    @Test(.timeLimit(.minutes(1)))
    func `Joining an established observation reloads fresh cached holdings`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let pages = ObservedPages()
        let service = fixture.service(pages: pages)
        var first = await service.observations(for: "wallet").makeAsyncIterator()
        try await nextResult(&first)
        await pages.set(slot: 101, units: 200)

        var joined = await service.observations(for: "wallet").makeAsyncIterator()
        let initial = try #require(await joined.next())
        try #require(initial.isRefreshing)
        let refreshed = try await nextResult(&joined)
        #expect(refreshed.holdings.first?.amount?.units == 200)
        #expect(refreshed.snapshot?.lastIndexedSlot == 101)
        #expect(await pages.readCount == 2)
        #expect(fixture.socket.requests.count == 3)
        try await service.removeData(for: "wallet")
    }

    /// Verifies releasing the final stream stops observation even when its consumer exits normally.
    @Test(.timeLimit(.minutes(1)))
    func `Leaving portfolio observation scope closes its connection`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let service = fixture.service(pages: ObservedPages())
        let initial = try await firstObservation(from: service)
        #expect(initial.error == nil)
        await fixture.socket.waitUntilCancelled()
        #expect(fixture.store.snapshot(for: fixture.key) == initial.snapshot)
    }

    /// Verifies a confirmed change bypasses fresh cache and waits for indexed holdings before saving.
    @Test(.timeLimit(.minutes(1)))
    func `Confirmed changes refresh fresh portfolios after DAS catches up`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let pages = ObservedPages()
        let service = fixture.service(pages: pages)
        var updates = await service.observations(for: "wallet").makeAsyncIterator()
        let initial = try await nextResult(&updates)
        let original = try #require(initial.snapshot)
        #expect(original.lastIndexedSlot == 100)
        #expect(fixture.socket.requests.count == 3)

        await pages.set(slot: 108, units: 200)
        fixture.socket.notify(slot: 110, subscription: 3, method: "programNotification")
        var delays = fixture.gate.delays.makeAsyncIterator()
        #expect(await delays.next() == .seconds(2))
        fixture.gate.resume()
        #expect(await delays.next() == .seconds(2))
        #expect(fixture.store.snapshot(for: fixture.key) == original)
        await pages.set(slot: 110, units: 200)
        fixture.gate.resume()
        let updated = try await nextResult(&updates)
        #expect(updated.error == nil)
        #expect(updated.snapshot?.lastIndexedSlot == 110)
        #expect(updated.holdings.first?.amount?.units == 200)
        #expect(fixture.store.snapshot(for: fixture.key) == updated.snapshot)
        #expect(await pages.readCount == 3)
        try await service.removeData(for: "wallet")
        await fixture.socket.waitUntilCancelled()
    }

    /// Verifies missing and lagging watermarks receive only bounded follow-ups and never renew stale cache.
    /// - Parameter watermark: The indexer's outdated or unavailable slot.
    @Test(.timeLimit(.minutes(1)), arguments: [UInt64(99), nil])
    func `Indexer lag is bounded and leaves ordinary reads invalidated`(watermark: UInt64?) async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let pages = ObservedPages()
        let service = fixture.service(pages: pages)
        var updates = await service.observations(for: "wallet").makeAsyncIterator()
        let original = try await nextResult(&updates)
        await pages.set(slot: watermark, units: 999)
        fixture.socket.notify(slot: 101)
        var delays = fixture.gate.delays.makeAsyncIterator()
        for _ in 0..<3 {
            #expect(await delays.next() == .seconds(2))
            fixture.gate.resume()
        }
        let failed = try await nextResult(&updates)
        #expect(failed.error as? ObservationError == .indexingBehind(expected: 101, observed: watermark))
        #expect(failed.snapshot == original.snapshot)
        #expect(await pages.readCount == 4)
        #expect(fixture.store.snapshot(for: fixture.key) == original.snapshot)

        var ordinary = await service.updates(for: "wallet").makeAsyncIterator()
        #expect(try #require(await ordinary.next()).isRefreshing)
        let stillBehind = try #require(await ordinary.next())
        #expect(stillBehind.error as? ObservationError == .indexingBehind(expected: 101, observed: watermark))
        #expect(await pages.readCount == 5)
        try await service.removeData(for: "wallet")
        await fixture.socket.waitUntilCancelled()
    }

    /// Verifies HTTP failure ends reconciliation immediately instead of using its lag retry budget.
    @Test(.timeLimit(.minutes(1)))
    func `Observation does not retry failed RPC requests`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let pages = ObservedPages()
        let service = fixture.service(pages: pages)
        var updates = await service.observations(for: "wallet").makeAsyncIterator()
        let initial = try await nextResult(&updates)
        await pages.fail()
        fixture.socket.notify(slot: 101)
        var delays = fixture.gate.delays.makeAsyncIterator()
        _ = try #require(await delays.next())
        fixture.gate.resume()
        let failed = try await nextResult(&updates)
        #expect(failed.error as? RPCError == .transport(.notConnectedToInternet))
        #expect(failed.snapshot == initial.snapshot)
        #expect(await pages.readCount == 2)
        try await service.removeData(for: "wallet")
        await fixture.socket.waitUntilCancelled()
    }

    /// Verifies a change arriving during a paced price lookup cannot make older holdings appear fresh.
    @Test(.timeLimit(.minutes(1)))
    func `Changes received during pricing prevent stale holdings from being saved`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let pages = ObservedPages()
        let service = fixture.service(pages: pages)
        var initial = await service.updates(for: "wallet").makeAsyncIterator()
        let original = try await nextResult(&initial)
        let http = AssetResponses { try await pages.response($0) }
        let prices = PriceResponses { _ in
            try await fixture.gate.pause(.zero)
            return Data("{}".utf8)
        }
        let coordinator = RefreshCoordinator(source: SnapshotFetcher(rpc: http.client, pageSize: 1_000), store: fixture.store,
                                             prices: prices.client)
        var updates = await coordinator.updates(for: "wallet", policy: .reload).makeAsyncIterator()
        var started = fixture.gate.delays.makeAsyncIterator()
        _ = try #require(await started.next())
        await coordinator.requireIndexedSlot(101, for: "wallet")
        fixture.gate.resume()
        let failed = try await nextResult(&updates)
        #expect(failed.error as? ObservationError == .indexingBehind(expected: 101, observed: 100))
        #expect(failed.snapshot == original.snapshot)
        #expect(fixture.store.snapshot(for: fixture.key) == original.snapshot)
        #expect(await coordinator.hasPendingChanges(for: "wallet"))
        #expect(await pages.readCount == 2)
        #expect(await prices.requests.count == 1)
    }

    /// Verifies separate consumers share one connection and the last cancellation closes it.
    @Test(.timeLimit(.minutes(1)))
    func `Portfolio observers share a connection until the final consumer leaves`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let pages = ObservedPages()
        let service = fixture.service(pages: pages)
        let first = await service.observations(for: "wallet")
        let second = await service.observations(for: "wallet")
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
        #expect(await pages.readCount == 1)

        let last = Task { for await _ in second {} }
        last.cancel()
        await last.value
        await fixture.socket.waitUntilCancelled()
        #expect(fixture.store.snapshot(for: fixture.key) != nil)
    }

    /// Verifies removing a wallet cancels queued catch-up and prevents deleted data from returning.
    @Test(.timeLimit(.minutes(1)))
    func `Removing a watched wallet cancels queued reconciliation`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let pages = ObservedPages()
        let service = fixture.service(pages: pages)
        var updates = await service.observations(for: "wallet").makeAsyncIterator()
        try await nextResult(&updates)
        fixture.socket.notify(slot: 101)
        var delays = fixture.gate.delays.makeAsyncIterator()
        _ = try #require(await delays.next())
        try await service.removeData(for: "wallet")
        await fixture.socket.waitUntilCancelled()
        #expect(await updates.next() == nil)
        #expect(fixture.store.snapshot(for: fixture.key) == nil)
        #expect(await pages.readCount == 1)
    }

    /// Verifies socket errors are visible, retain holdings, and end the watch without reconnecting.
    @Test(.timeLimit(.minutes(1)))
    func `Subscription failure ends portfolio observation with cached holdings`() async throws {
        let fixture = ObservationFixture()
        defer { fixture.cleanUp() }
        let service = fixture.service(pages: ObservedPages())
        var updates = await service.observations(for: "wallet").makeAsyncIterator()
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
        let das = AssetResponses { _ in throw URLError(.notConnectedToInternet) }
        let changes = Solana(network: .devnet, transport: das, socket: { _ in fixture.socket })
        let service = Portfolio(rpc: das.client, store: fixture.store, changes: changes)
        var updates = await service.observations(for: "wallet").makeAsyncIterator()
        let failed = try await nextResult(&updates)
        #expect(failed.error as? ObservationError == .networkMismatch)
        #expect(await updates.next() == nil)
        #expect(fixture.socket.requests.isEmpty)
        #expect(await das.requests.isEmpty)
    }
}

/// Holds successful DAS responses behind a controllable indexing watermark.
private actor ObservedPages {
    private var slot: UInt64? = 100
    private var units: UInt64 = 100
    private var offline = false
    private(set) var readCount = 0

    /// Updates the next successful DAS response.
    /// - Parameters:
    ///   - slot: Its indexing watermark, or `nil` if unavailable.
    ///   - units: The native balance returned by the indexer.
    func set(slot: UInt64?, units: UInt64) { self.slot = slot; self.units = units }

    /// Makes subsequent requests fail instead of returning an outdated successful response.
    func fail() { offline = true }

    /// Returns a native-only holdings page through the actual Helius decoder.
    /// - Parameter request: The encoded DAS request decoded by the HTTP fixture.
    /// - Returns: A page with the configured indexing watermark and balance.
    /// - Throws: An offline error when configured to fail.
    func response(_ request: GetFungibleAssetsByOwner) throws -> Data {
        readCount += 1
        if offline { throw URLError(.notConnectedToInternet) }
        let watermark = slot.map { #", "last_indexed_slot":\#($0)"# } ?? ""
        return Data(#"{"page":\#(request.page),"limit":1000,"items":[],"nativeBalance":{"lamports":\#(units)}\#(watermark)}"#.utf8)
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
    let key = CacheKey(owner: "wallet", network: .mainnet)
    var store: FileSnapshotStore { FileSnapshotStore(directory: directory) }

    /// Composes a real Helius client with controlled network boundaries and the production Portfolio.
    /// - Parameter pages: The indexer response state.
    /// - Returns: The portfolio service whose observation behavior is exercised.
    func service(pages: ObservedPages) -> Portfolio {
        let http = AssetResponses { try await pages.response($0) }
        let rpc = HeliusRPC(apiKey: "fixture-key", network: .mainnet, transport: http, socket: { _ in socket })
        return Portfolio(rpc: rpc, store: store, pause: { try await gate.pause($0) })
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
    var iterator = await service.observations(for: "wallet").makeAsyncIterator()
    return try await nextResult(&iterator)
}
