import Foundation
import RPC

/// Serializes cache access and shares each wallet's active refresh between consumers.
actor RefreshCoordinator {
    private let source: any SnapshotFetching
    private let store: any SnapshotStoring
    private let pricer: SnapshotPricer?
    private let now: @Sendable () -> Date
    private var flights: [CacheKey: Flight] = [:]
    private var requiredSlots: [CacheKey: UInt64] = [:]

    /// Creates a coordinator with independent network and storage dependencies.
    ///
    /// - Parameters:
    ///   - source: The complete-snapshot source.
    ///   - store: The persistent snapshot store.
    ///   - prices: An optional price provider used for full and price-only refreshes.
    ///   - now: The clock for freshness checks and successful price retrievals.
    init(source: any SnapshotFetching, store: any SnapshotStoring, prices: (any PriceProviding)? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        self.store = store
        self.now = now
        pricer = prices.map { SnapshotPricer(provider: $0, now: now) }
    }

    /// Registers an independent update stream and starts or joins the wallet's refresh.
    ///
    /// - Parameters:
    ///   - owner: The wallet whose holdings to retrieve.
    ///   - scope: Whether to refresh all data or only the cached holdings' prices.
    ///   - policy: Whether to reuse fresh data or perform a network refresh regardless of age.
    /// - Returns: A registered stream, or a finished stream if the calling task is cancelled.
    func updates(for owner: String, scope: Scope = .holdings, policy: RefreshPolicy) -> AsyncStream<Update> {
        let (stream, continuation) = AsyncStream<Update>.makeStream(bufferingPolicy: .bufferingNewest(2))
        guard !Task.isCancelled else {
            continuation.finish()
            return stream
        }
        let key = CacheKey(owner: owner, network: source.network)
        let cached = store.snapshot(for: key)
        if scope == .prices, pricer == nil {
            continuation.yield(Update(snapshot: cached, phase: .refreshing))
            continuation.yield(Update(snapshot: cached, phase: .failed(PriceError.providerUnavailable)))
            continuation.finish()
            return stream
        }
        let requiredScope = scope == .holdings && requiredSlots[key] != nil
            ? .holdings : scopeRequiringRefresh(scope, policy: policy, cached: cached)
        let id = UUID()
        continuation.onTermination = { @Sendable _ in
            Task { @concurrent in await self.unsubscribe(key: key, id: id) }
        }
        if var flight = flights[key] {
            flight.consumers[id] = continuation
            if let initial = flight.initial { continuation.yield(initial) }
            if requiredScope == .holdings, flight.scope == .prices {
                // A full refresh also satisfies price consumers; obsolete price work cannot overwrite its balances.
                flight.task?.cancel()
                flight.generation = UUID()
                flight.scope = .holdings
                let generation = flight.generation
                flight.task = Task { await refresh(key: key, generation: generation) }
            }
            flights[key] = flight
            return stream
        }
        guard let requiredScope else {
            continuation.yield(Update(snapshot: cached, phase: .ready))
            continuation.finish()
            return stream
        }
        let generation = UUID()
        flights[key] = Flight(generation: generation, scope: requiredScope, consumers: [id: continuation])
        flights[key]?.task = Task { await refresh(key: key, generation: generation) }
        return stream
    }

    /// Reads current complete holdings for observation state without triggering network work.
    /// - Parameter owner: The wallet whose cached snapshot to retrieve.
    /// - Returns: Its complete snapshot, or `nil` if unavailable.
    func cachedSnapshot(for owner: String) -> Snapshot? {
        store.snapshot(for: CacheKey(owner: owner, network: source.network))
    }

    /// Invalidates cache freshness until DAS reaches a confirmed change slot.
    /// - Parameters:
    ///   - slot: The latest confirmed change observed for this wallet.
    ///   - owner: The wallet whose holdings require reconciliation.
    func requireIndexedSlot(_ slot: UInt64, for owner: String) {
        guard !Task.isCancelled else { return }
        let key = CacheKey(owner: owner, network: source.network)
        requiredSlots[key] = max(requiredSlots[key] ?? 0, slot)
    }

    /// Reports whether observed changes still require a complete holdings refresh.
    /// - Parameter owner: The wallet to inspect.
    /// - Returns: Whether a confirmed change remains unreconciled.
    func hasPendingChanges(for owner: String) -> Bool {
        requiredSlots[CacheKey(owner: owner, network: source.network)] != nil
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
        requiredSlots.removeValue(forKey: key)
        if let flight = flights.removeValue(forKey: key) {
            flight.task?.cancel()
            for continuation in flight.consumers.values { continuation.finish() }
        }
        try store.remove(for: key)
    }

    /// Emits existing state, fetches all holdings, and commits one complete update.
    ///
    /// - Parameters:
    ///   - key: The wallet and network being refreshed.
    ///   - generation: The identity of this refresh, used to reject obsolete results.
    private func refresh(key: CacheKey, generation: UUID) async {
        guard let flight = flights[key], flight.generation == generation else { return }
        let cached = store.snapshot(for: key)
        if flight.initial == nil {
            let initial = Update(snapshot: cached, phase: .refreshing)
            flights[key]?.initial = initial
            for continuation in flights[key]?.consumers.values ?? [:].values { continuation.yield(initial) }
        }

        var available = cached
        do {
            try pricer?.validate(network: source.network)
            let snapshot: Snapshot
            switch flight.scope {
            case .holdings:
                let holdings = try await source.snapshot(for: key.owner)
                try validateIndex(holdings, for: key)
                snapshot = try await pricer?.snapshot(pricing: holdings) ?? holdings
            case .prices:
                guard let pricer else { throw PriceError.providerUnavailable }
                guard let cached else { throw PriceError.holdingsUnavailable }
                snapshot = try await pricer.snapshot(pricing: cached)
            }
            try Task.checkCancellation()
            guard flights[key]?.generation == generation else { return }
            if flight.scope == .holdings { try validateIndex(snapshot, for: key) }
            available = snapshot
            try store.save(snapshot, for: key)
            if flight.scope == .holdings { requiredSlots.removeValue(forKey: key) }
            finish(key: key, generation: generation, update: Update(snapshot: snapshot, phase: .ready))
        } catch {
            let update = Task.isCancelled ? nil : Update(snapshot: available, phase: .failed(error))
            finish(key: key, generation: generation, update: update)
        }
    }

    /// Rejects a stale indexer result before pricing or persisting it as fresh.
    /// - Parameters:
    ///   - snapshot: The complete DAS response to validate.
    ///   - key: The wallet and network associated with any pending change.
    /// - Throws: An indexing error when the watermark is missing or behind the observed change.
    private func validateIndex(_ snapshot: Snapshot, for key: CacheKey) throws {
        if let expected = requiredSlots[key], snapshot.lastIndexedSlot.map({ $0 >= expected }) != true {
            throw ObservationError.indexingBehind(expected: expected, observed: snapshot.lastIndexedSlot)
        }
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
        var consumers: [UUID: AsyncStream<Update>.Continuation]
        var initial: Update?
        var task: Task<Void, Never>?
    }

    /// The data refreshed by one shared operation.
    enum Scope {
        /// Retrieve holdings and metadata, then independent quotes when configured.
        case holdings
        /// Revalue existing holdings without querying DAS.
        case prices
    }
}
