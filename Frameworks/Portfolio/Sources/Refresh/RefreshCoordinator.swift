import Foundation
import RPC

/// Serializes cache access and shares each wallet's active refresh between consumers.
actor RefreshCoordinator {
    private let source: any BalanceReading
    private let store: any SnapshotStoring
    private let pricer: SnapshotPricer?
    private let logos: LogoReader?
    private let now: @Sendable () -> Date
    private var flights: [CacheKey: Flight] = [:]
    private var revision: UInt64 = 0
    private var snapshotRevisions: [CacheKey: UInt64] = [:]

    /// Creates a coordinator with independent network and storage dependencies.
    ///
    /// - Parameters:
    ///   - source: The balance source.
    ///   - store: The persistent snapshot store.
    ///   - prices: An optional price provider used for full and price-only refreshes.
    ///   - logos: An optional provider of logo copies for the listed tokens after each balance read.
    ///   - now: The clock for freshness checks and successful price retrievals.
    init(source: any BalanceReading, store: any SnapshotStoring, prices: (any PriceProviding)? = nil,
         logos: (any LogoProviding)? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        self.store = store
        self.now = now
        pricer = prices.map { SnapshotPricer(provider: $0, now: now) }
        self.logos = logos.map { LogoReader(provider: $0) }
    }

    /// Registers an independent update stream and starts or joins the wallet's refresh.
    ///
    /// - Parameters:
    ///   - owner: The wallet whose holdings to retrieve.
    ///   - scope: Whether to refresh all data or only the cached holdings' prices.
    ///   - policy: Whether to reuse fresh data or perform a network refresh regardless of age.
    ///   - minContextSlot: The earliest acceptable observation for a scheduled balance read, or `nil`.
    /// - Returns: A registered stream, or a finished stream if the calling task is cancelled.
    func updates(for owner: String, scope: Scope = .holdings, policy: RefreshPolicy,
                 minContextSlot: UInt64? = nil) -> AsyncStream<Update> {
        let (stream, continuation) = AsyncStream<Update>.makeStream(bufferingPolicy: .bufferingNewest(2))
        guard !Task.isCancelled else {
            continuation.finish()
            return stream
        }
        let key = CacheKey(owner: owner, network: source.network)
        let cached = store.snapshot(for: key)
        if scope == .prices, pricer == nil {
            continuation.yield(makeUpdate(snapshot: cached, phase: .refreshing, snapshotRevision: snapshotRevisions[key] ?? 0))
            continuation.yield(makeUpdate(snapshot: cached, phase: .failed(PriceError.providerUnavailable),
                                          snapshotRevision: snapshotRevisions[key] ?? 0))
            continuation.finish()
            return stream
        }
        let requiredScope = scopeRequiringRefresh(scope, policy: policy, cached: cached)
        let id = UUID()
        continuation.onTermination = { @Sendable _ in
            Task { @concurrent in await self.unsubscribe(key: key, id: id) }
        }
        if var flight = flights[key] {
            flight.consumers[id] = continuation
            if let initial = flight.initial { continuation.yield(initial) }
            let needsNewerContext = (minContextSlot ?? 0) > (flight.minContextSlot ?? 0)
            if needsNewerContext || (requiredScope == .holdings && flight.scope == .prices) {
                // Keep every consumer, but replace work that cannot satisfy the stronger balance request.
                flight.scope = .holdings
                if needsNewerContext { flight.minContextSlot = minContextSlot }
                restart(&flight, key: key)
            }
            flights[key] = flight
            return stream
        }
        guard let requiredScope else {
            continuation.yield(makeUpdate(snapshot: cached, phase: .ready, snapshotRevision: snapshotRevisions[key] ?? 0))
            continuation.finish()
            return stream
        }
        let generation = UUID()
        flights[key] = Flight(generation: generation, scope: requiredScope, minContextSlot: minContextSlot,
                              consumers: [id: continuation])
        flights[key]?.task = Task { await refresh(key: key, generation: generation) }
        return stream
    }

    /// Starts a balance read in progress again, so that it reads the account's current token list.
    ///
    /// Its consumers keep waiting and receive only the new read's result.
    /// - Parameter owner: The account whose token list changed.
    func restartBalanceRead(for owner: String) {
        let key = CacheKey(owner: owner, network: source.network)
        guard var flight = flights[key], flight.scope == .holdings else { return }
        restart(&flight, key: key)
        flights[key] = flight
    }

    /// Takes a removed token out of the saved snapshot, so no consumer or later launch shows it before the next read.
    ///
    /// The snapshot gets a new revision, so consumers that receive it replace their older copy. A refresh in progress
    /// starts again in the same step, so no read of the previous list can save over the edited snapshot.
    /// - Parameters:
    ///   - id: The removed token's identity.
    ///   - owner: The account whose token list no longer holds the token.
    /// - Throws: An encoding or file-system error if the snapshot can't be saved; the refresh starts again either way.
    func removeHolding(_ id: Holding.Identity, for owner: String) throws {
        let key = CacheKey(owner: owner, network: source.network)
        defer {
            if var flight = flights[key] {
                // The restarted refresh sends its consumers the edited snapshot instead of the earlier one.
                flight.initial = nil
                restart(&flight, key: key)
                flights[key] = flight
            }
        }
        guard let cached = store.snapshot(for: key), cached.holdings.contains(where: { $0.id == id }) else { return }
        let snapshot = Snapshot(owner: cached.owner, network: cached.network,
                                holdings: cached.holdings.filter { $0.id != id },
                                fetchedAt: cached.fetchedAt, pricesFetchedAt: cached.pricesFetchedAt)
        try store.save(snapshot, for: key)
        revision += 1
        snapshotRevisions[key] = revision
    }

    /// Orders observation status in the same sequence as manual and price refreshes.
    /// - Parameters:
    ///   - owner: The wallet whose cached holdings accompany the status.
    ///   - phase: The connection's progress or failure.
    /// - Returns: Cached holdings and an ordered state without requesting network work.
    func status(for owner: String, phase: Update.Phase) -> Update {
        let key = CacheKey(owner: owner, network: source.network)
        return makeUpdate(snapshot: store.snapshot(for: key), phase: phase,
                          snapshotRevision: snapshotRevisions[key] ?? 0)
    }

    /// Allocates a service-local order while retaining the snapshot's own original order.
    /// - Parameters:
    ///   - snapshot: The available complete holdings.
    ///   - phase: The current operation status.
    ///   - snapshotRevision: The snapshot's existing order, or zero for an initial disk cache.
    /// - Returns: A state that can be merged across independently delivered streams.
    private func makeUpdate(snapshot: Snapshot?, phase: Update.Phase, snapshotRevision: UInt64) -> Update {
        revision += 1
        return Update(snapshot: snapshot, phase: phase, revision: revision, snapshotRevision: snapshotRevision)
    }

    /// Selects only the data whose retrieval time requires another request.
    /// - Parameters:
    ///   - scope: The data requested by the consumer.
    ///   - policy: Whether freshness checks may skip networking.
    ///   - cached: The wallet's preceding complete snapshot, if any.
    /// - Returns: Required network work, or `nil` when the cached snapshot is sufficient.
    private func scopeRequiringRefresh(_ scope: Scope, policy: RefreshPolicy, cached: Snapshot?) -> Scope? {
        guard policy == .ifStale, let cached else { return scope }
        // A fresh cache must not hide a misconfigured provider's network error.
        if let pricer, pricer.provider.network != source.network { return scope }
        let currentTime = now()
        if scope == .holdings, !isFresh(cached.fetchedAt, at: currentTime) { return .holdings }
        if pricer != nil, !isFresh(cached.pricesFetchedAt, at: currentTime) { return .prices }
        return nil
    }

    /// Checks the five-minute lifetime without treating future or invalid dates as fresh.
    /// - Parameters:
    ///   - retrievedAt: The last successful retrieval time, or `nil` if not yet checked.
    ///   - currentTime: The clock value shared by this request's freshness checks.
    /// - Returns: Whether the timestamp is less than five minutes old and not in the future.
    private func isFresh(_ retrievedAt: Date?, at currentTime: Date) -> Bool {
        guard let retrievedAt else { return false }
        let age = currentTime.timeIntervalSince(retrievedAt)
        return age.isFinite && age >= 0 && age < 300
    }

    /// Detaches one consumer and cancels work only when no consumers remain.
    ///
    /// - Parameters:
    ///   - key: The wallet and network being observed.
    ///   - id: The departing consumer's identifier.
    private func unsubscribe(key: CacheKey, id: UUID) {
        guard var flight = flights[key] else { return }
        flight.consumers.removeValue(forKey: id)
        if flight.consumers.isEmpty {
            flights.removeValue(forKey: key)
            flight.task?.cancel()
        } else {
            flights[key] = flight
        }
    }

    /// Removes local data and prevents an older refresh from recreating it.
    ///
    /// - Parameter owner: The wallet whose local data to remove.
    /// - Throws: A file-system error if the saved snapshot can't be removed.
    func removeData(for owner: String) throws {
        let key = CacheKey(owner: owner, network: source.network)
        endRefresh(for: key)
        try store.remove(for: key)
        snapshotRevisions.removeValue(forKey: key)
    }

    /// Ends every refresh and removes logos from this network's saved snapshots after an RPC provider change.
    ///
    /// Each snapshot gets a newer snapshot revision, so consumers replace copies that show the previous
    /// provider's logos.
    /// - Throws: A file-system error if the snapshots can't be listed or one can't be rewritten.
    func providerDidChange() throws {
        for key in flights.keys { endRefresh(for: key) }
        // A revision newer than any snapshot that consumers already hold.
        revision += 1
        for snapshot in try store.snapshots() where snapshot.network == source.network {
            let key = CacheKey(owner: snapshot.owner, network: snapshot.network)
            let stripped = snapshot.replacingLogos(with: [:])
            if stripped != snapshot { try store.save(stripped, for: key) }
            snapshotRevisions[key] = revision
        }
    }

    /// Cancels a wallet's refresh and ends its consumers' streams, so the refresh can't deliver or save a result.
    /// - Parameter key: The wallet and network whose refresh ends.
    private func endRefresh(for key: CacheKey) {
        guard let flight = flights.removeValue(forKey: key) else { return }
        flight.task?.cancel()
        for continuation in flight.consumers.values { continuation.finish() }
    }

    /// Emits existing state, reads all balances, and commits one complete update.
    ///
    /// - Parameters:
    ///   - key: The wallet and network being refreshed.
    ///   - generation: The identity of this refresh, used to reject obsolete results.
    private func refresh(key: CacheKey, generation: UUID) async {
        guard let flight = flights[key], flight.generation == generation else { return }
        let cached = store.snapshot(for: key)
        if flight.initial == nil {
            let initial = makeUpdate(snapshot: cached, phase: .refreshing, snapshotRevision: snapshotRevisions[key] ?? 0)
            flights[key]?.initial = initial
            for continuation in flights[key]?.consumers.values ?? [:].values { continuation.yield(initial) }
        }

        var available = cached
        var availableRevision = snapshotRevisions[key] ?? 0
        do {
            try pricer?.validate(network: source.network)
            let snapshot: Snapshot
            switch flight.scope {
            case .holdings:
                let balances = try await source.snapshot(for: key.owner, minContextSlot: flight.minContextSlot)
                let holdings = await logos?.snapshot(addingLogosTo: balances, keeping: cached) ?? balances
                snapshot = try await pricer?.snapshot(pricing: holdings) ?? holdings
            case .prices:
                guard let pricer else { throw PriceError.providerUnavailable }
                guard let cached else { throw PriceError.holdingsUnavailable }
                snapshot = try await pricer.snapshot(pricing: cached)
            }
            try Task.checkCancellation()
            guard flights[key]?.generation == generation else { return }
            available = snapshot
            revision += 1
            availableRevision = revision
            try store.save(snapshot, for: key)
            snapshotRevisions[key] = availableRevision
            finish(key: key, generation: generation,
                   update: makeUpdate(snapshot: snapshot, phase: .ready, snapshotRevision: availableRevision))
        } catch {
            let update = Task.isCancelled ? nil
                : makeUpdate(snapshot: available, phase: .failed(error), snapshotRevision: availableRevision)
            finish(key: key, generation: generation, update: update)
        }
    }

    /// Replaces a refresh's work under a new generation, so the replaced work can't deliver its results.
    ///
    /// - Parameters:
    ///   - flight: The refresh whose consumers wait for the new work.
    ///   - key: The wallet and network being refreshed.
    private func restart(_ flight: inout Flight, key: CacheKey) {
        flight.task?.cancel()
        flight.generation = UUID()
        let generation = flight.generation
        flight.task = Task { await refresh(key: key, generation: generation) }
    }

    /// Delivers the final state and closes every consumer of the matching refresh.
    ///
    /// - Parameters:
    ///   - key: The cache identity being refreshed.
    ///   - generation: The refresh identity that must still be current.
    ///   - update: The final state, or `nil` for cancellation.
    private func finish(key: CacheKey, generation: UUID, update: Update?) {
        guard let flight = flights[key], flight.generation == generation else { return }
        flights.removeValue(forKey: key)
        for continuation in flight.consumers.values {
            if let update { continuation.yield(update) }
            continuation.finish()
        }
    }

    /// The consumers and task owned by one refresh generation.
    private struct Flight {
        var generation: UUID
        var scope: Scope
        var minContextSlot: UInt64?
        var consumers: [UUID: AsyncStream<Update>.Continuation]
        var initial: Update?
        var task: Task<Void, Never>?
    }

    /// The data refreshed by one shared operation.
    enum Scope {
        /// Read balances, then independent quotes when configured.
        case holdings
        /// Revalue existing holdings without reading balances again.
        case prices
    }
}
