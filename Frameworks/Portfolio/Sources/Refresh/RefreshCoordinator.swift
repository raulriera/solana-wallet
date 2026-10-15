import Foundation
import RPC

/// Serializes cache access and shares each wallet's active refresh between consumers.
actor RefreshCoordinator {
    private let source: any BalanceReading
    private let tokenLists: TokenListCoordinator
    private let store: any SnapshotStoring
    private let pricer: SnapshotPricer?
    private let logos: LogoReader?
    private var flights: [CacheKey: Flight] = [:]
    private var revision: UInt64 = 0
    private var snapshotRevisions: [CacheKey: UInt64] = [:]

    /// Creates a coordinator with independent network and storage dependencies.
    ///
    /// - Parameters:
    ///   - source: The balance source.
    ///   - tokenLists: The token lists whose tokens each balance read covers.
    ///   - store: The persistent snapshot store.
    ///   - prices: An optional price provider for the listed tokens.
    ///   - logos: An optional provider of logo copies for the listed tokens.
    init(source: any BalanceReading, tokenLists: TokenListCoordinator, store: any SnapshotStoring,
         prices: (any PriceProviding)?, logos: (any LogoProviding)?) {
        self.source = source
        self.tokenLists = tokenLists
        self.store = store
        pricer = prices.map { SnapshotPricer(provider: $0) }
        self.logos = logos.map { LogoReader(provider: $0) }
    }

    /// Registers an independent update stream and starts or joins the wallet's refresh.
    ///
    /// - Parameters:
    ///   - owner: The wallet whose holdings to retrieve.
    ///   - minContextSlot: The earliest acceptable observation for a scheduled balance read, or `nil`.
    /// - Returns: A registered stream, or a finished stream if the calling task is cancelled.
    func updates(for owner: String, minContextSlot: UInt64? = nil) -> AsyncStream<Update> {
        guard !Task.isCancelled else { return AsyncStream { $0.finish() } }
        let key = CacheKey(owner: owner, network: source.network)
        let unsubscribe: @Sendable (UUID) async -> Void = { id in await self.unsubscribe(key: key, id: id) }
        if var flight = flights[key] {
            let stream = flight.consumers.add(first: flight.initial, onEnd: unsubscribe)
            if (minContextSlot ?? 0) > (flight.minContextSlot ?? 0) {
                // Keep every consumer, but replace work that cannot satisfy the newer balance request.
                flight.minContextSlot = minContextSlot
                restart(&flight, key: key)
            }
            flights[key] = flight
            return stream
        }
        let generation = UUID()
        var consumers = UpdateConsumers()
        let stream = consumers.add(onEnd: unsubscribe)
        flights[key] = Flight(generation: generation, minContextSlot: minContextSlot, consumers: consumers)
        flights[key]?.task = Task { await refresh(key: key, generation: generation) }
        return stream
    }

    /// Starts a balance read in progress again, so that it reads the account's current token list.
    ///
    /// Its consumers keep waiting and receive only the new read's result.
    /// - Parameter owner: The account whose token list changed.
    func restartBalanceRead(for owner: String) {
        let key = CacheKey(owner: owner, network: source.network)
        guard var flight = flights[key] else { return }
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
        guard var snapshot = store.snapshot(for: key), snapshot.holdings.contains(where: { $0.id == id }) else {
            return
        }
        snapshot.holdings.removeAll { $0.id == id }
        try store.save(snapshot, for: key)
        revision += 1
        snapshotRevisions[key] = revision
    }

    /// Orders observation status in the same sequence as manual refreshes.
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

    /// Detaches one consumer and cancels work only when no consumers remain.
    ///
    /// - Parameters:
    ///   - key: The wallet and network being observed.
    ///   - id: The departing consumer's identifier.
    private func unsubscribe(key: CacheKey, id: UUID) {
        guard var flight = flights[key] else { return }
        flight.consumers.remove(id)
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
        flight.consumers.finish()
    }

    /// Emits existing state, reads all balances with their logos and prices, and commits one complete update.
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
            flights[key]?.consumers.send(initial)
        }

        var available = cached
        var availableRevision = snapshotRevisions[key] ?? 0
        do {
            let list = try await tokenLists.list(for: key.owner)
            let holdings = list.holdingIDs
            // Logos and prices need only the listed tokens, so they're looked up while balances are read.
            async let balances = source.snapshot(of: list, for: key.owner, minContextSlot: flight.minContextSlot)
            async let logoLookup = logos?.logos(for: holdings, keeping: cached)
            async let quoteLookup = pricer?.quotes(for: holdings)
            var snapshot = try await balances
            if let found = await logoLookup { snapshot = snapshot.replacingLogos(with: found) }
            if let pricer, let quotes = try await quoteLookup {
                snapshot = try pricer.snapshot(pricing: snapshot, with: quotes)
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
        if let update { flight.consumers.send(update) }
        flight.consumers.finish()
    }

    /// The consumers and task owned by one refresh generation.
    private struct Flight {
        var generation: UUID
        var minContextSlot: UInt64?
        var consumers: UpdateConsumers
        var initial: Update?
        var task: Task<Void, Never>?
    }
}
