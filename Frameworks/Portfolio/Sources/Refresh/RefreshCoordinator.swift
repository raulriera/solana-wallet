import Foundation
import RPC

/// An actor that serializes cache access and shares each wallet's refresh between its consumers.
actor RefreshCoordinator {
    private let source: any BalanceReading
    private let tokenLists: TokenListCoordinator
    private let store: any SnapshotStoring
    private let pricer: SnapshotPricer?
    private let logos: LogoReader?
    private var flights: [CacheKey: Flight] = [:]
    private var revision: UInt64 = 0
    private var snapshotRevisions: [CacheKey: UInt64] = [:]

    /// Creates a refresh coordinator.
    ///
    /// - Parameters:
    ///   - source: The balance reader.
    ///   - tokenLists: The token lists to read balances for.
    ///   - store: The snapshot store.
    ///   - prices: The price provider, or `nil` for no prices.
    ///   - logos: The logo provider, or `nil` for no logos.
    init(source: any BalanceReading, tokenLists: TokenListCoordinator, store: any SnapshotStoring,
         prices: (any PriceProviding)?, logos: (any LogoProviding)?) {
        self.source = source
        self.tokenLists = tokenLists
        self.store = store
        pricer = prices.map { SnapshotPricer(provider: $0) }
        self.logos = logos.map { LogoReader(provider: $0) }
    }

    /// Adds an update stream and starts or joins the wallet's refresh.
    ///
    /// - Parameters:
    ///   - owner: The wallet address.
    ///   - minContextSlot: The earliest slot the balance read may come from, or `nil` for any slot.
    /// - Returns: The consumer's stream, or a finished stream if the task is cancelled.
    func updates(for owner: String, minContextSlot: UInt64? = nil) -> AsyncStream<Update> {
        guard !Task.isCancelled else { return AsyncStream { $0.finish() } }
        let key = CacheKey(owner: owner, network: source.network)
        let unsubscribe: @Sendable (UUID) async -> Void = { id in await self.unsubscribe(key: key, id: id) }
        if var flight = flights[key] {
            let stream = flight.consumers.add(first: flight.initial, onEnd: unsubscribe)
            if (minContextSlot ?? 0) > (flight.minContextSlot ?? 0) {
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

    /// Starts an account's balance read in progress again.
    ///
    /// - Parameter owner: The account's wallet address.
    func restartBalanceRead(for owner: String) {
        let key = CacheKey(owner: owner, network: source.network)
        guard var flight = flights[key] else { return }
        restart(&flight, key: key)
        flights[key] = flight
    }

    /// Starts every balance read in progress again.
    func restartBalanceReads() {
        for key in flights.keys { restartBalanceRead(for: key.owner) }
    }

    /// Removes a holding from an account's saved snapshot and restarts the account's refresh.
    ///
    /// - Parameters:
    ///   - id: The holding's identity.
    ///   - owner: The account's wallet address.
    /// - Throws: An encoding or file-system error.
    func removeHolding(_ id: Holding.Identity, for owner: String) throws {
        let key = CacheKey(owner: owner, network: source.network)
        defer {
            if var flight = flights[key] {
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

    /// Returns an update with a wallet's cached snapshot and an observation phase.
    ///
    /// - Parameters:
    ///   - owner: The wallet address.
    ///   - phase: The connection's progress or failure.
    /// - Returns: An update with the next revision.
    func status(for owner: String, phase: Update.Phase) -> Update {
        let key = CacheKey(owner: owner, network: source.network)
        return makeUpdate(snapshot: store.snapshot(for: key), phase: phase,
                          snapshotRevision: snapshotRevisions[key] ?? 0)
    }

    /// Creates an update with the next revision.
    ///
    /// - Parameters:
    ///   - snapshot: The latest complete snapshot, or `nil`.
    ///   - phase: The refresh's phase.
    ///   - snapshotRevision: The snapshot's revision, or zero for a snapshot read from disk.
    /// - Returns: The new update.
    private func makeUpdate(snapshot: Snapshot?, phase: Update.Phase, snapshotRevision: UInt64) -> Update {
        revision += 1
        return Update(snapshot: snapshot, phase: phase, revision: revision, snapshotRevision: snapshotRevision)
    }

    /// Removes a consumer and cancels the refresh when none remain.
    ///
    /// - Parameters:
    ///   - key: The wallet and network.
    ///   - id: The consumer's identifier.
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

    /// Ends a wallet's refresh and removes its saved snapshot.
    ///
    /// - Parameter owner: The wallet address.
    /// - Throws: A file-system error.
    func removeData(for owner: String) throws {
        let key = CacheKey(owner: owner, network: source.network)
        endRefresh(for: key)
        try store.remove(for: key)
        snapshotRevisions.removeValue(forKey: key)
    }

    /// Ends every refresh and removes logos from the network's saved snapshots.
    ///
    /// - Throws: A file-system error.
    func providerDidChange() throws {
        for key in flights.keys { endRefresh(for: key) }
        revision += 1
        for snapshot in try store.snapshots() where snapshot.network == source.network {
            let key = CacheKey(owner: snapshot.owner, network: snapshot.network)
            let stripped = snapshot.replacingLogos(with: [:])
            if stripped != snapshot { try store.save(stripped, for: key) }
            snapshotRevisions[key] = revision
        }
    }

    /// Cancels a wallet's refresh and ends its consumers' streams.
    ///
    /// - Parameter key: The wallet and network.
    private func endRefresh(for key: CacheKey) {
        guard let flight = flights.removeValue(forKey: key) else { return }
        flight.task?.cancel()
        flight.consumers.finish()
    }

    /// Sends the cached state, then reads balances, logos, and prices and saves and sends the result.
    ///
    /// - Parameters:
    ///   - key: The wallet and network.
    ///   - generation: The refresh's generation.
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

    /// Restarts a refresh's work under a new generation.
    ///
    /// - Parameters:
    ///   - flight: The refresh to restart.
    ///   - key: The wallet and network.
    private func restart(_ flight: inout Flight, key: CacheKey) {
        flight.task?.cancel()
        flight.generation = UUID()
        let generation = flight.generation
        flight.task = Task { await refresh(key: key, generation: generation) }
    }

    /// Sends a refresh's final update and ends its consumers' streams.
    ///
    /// - Parameters:
    ///   - key: The wallet and network.
    ///   - generation: The refresh's generation, which must still be current.
    ///   - update: The final update, or `nil` to send none.
    private func finish(key: CacheKey, generation: UUID, update: Update?) {
        guard let flight = flights[key], flight.generation == generation else { return }
        flights.removeValue(forKey: key)
        if let update { flight.consumers.send(update) }
        flight.consumers.finish()
    }

    /// A wallet's refresh, with its consumers and task.
    private struct Flight {
        var generation: UUID
        var minContextSlot: UInt64?
        var consumers: UpdateConsumers
        var initial: Update?
        var task: Task<Void, Never>?
    }
}
