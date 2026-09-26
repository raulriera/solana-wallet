import Foundation

/// Serializes cache access and shares each wallet's active refresh between consumers.
actor RefreshCoordinator {
    private let source: any SnapshotFetching
    private let store: any SnapshotStoring
    private var flights: [CacheKey: Flight] = [:]

    /// Creates a coordinator with independent network and storage dependencies.
    ///
    /// - Parameters:
    ///   - source: The complete-snapshot source.
    ///   - store: The persistent snapshot store.
    init(source: any SnapshotFetching, store: any SnapshotStoring) {
        self.source = source
        self.store = store
    }

    /// Registers an independent update stream and starts or joins the wallet's refresh.
    ///
    /// - Parameter owner: The wallet whose holdings to retrieve.
    /// - Returns: A registered stream, or a finished stream if the calling task is cancelled.
    func updates(for owner: String) -> AsyncStream<Update> {
        let (stream, continuation) = AsyncStream<Update>.makeStream(bufferingPolicy: .bufferingNewest(2))
        guard !Task.isCancelled else {
            continuation.finish()
            return stream
        }
        let id = UUID()
        let key = CacheKey(owner: owner, network: source.network)
        continuation.onTermination = { @Sendable _ in
            Task { @concurrent in await self.unsubscribe(key: key, id: id) }
        }
        if var flight = flights[key] {
            flight.consumers[id] = continuation
            flights[key] = flight
            if let initial = flight.initial { continuation.yield(initial) }
            return stream
        }
        let generation = UUID()
        flights[key] = Flight(generation: generation, consumers: [id: continuation])
        flights[key]?.task = Task { await refresh(key: key, generation: generation) }
        return stream
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
        guard flights[key]?.generation == generation else { return }
        let cached = store.snapshot(for: key)
        let initial = Update(snapshot: cached, phase: .refreshing)
        flights[key]?.initial = initial
        for continuation in flights[key]?.consumers.values ?? [:].values { continuation.yield(initial) }

        var available = cached
        do {
            let snapshot = try await source.snapshot(for: key.owner)
            try Task.checkCancellation()
            guard flights[key]?.generation == generation else { return }
            available = snapshot
            try store.save(snapshot, for: key)
            finish(key: key, generation: generation, update: Update(snapshot: snapshot, phase: .ready))
        } catch {
            let update = Task.isCancelled ? nil : Update(snapshot: available, phase: .failed(error))
            finish(key: key, generation: generation, update: update)
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
        let generation: UUID
        var consumers: [UUID: AsyncStream<Update>.Continuation]
        var initial: Update?
        var task: Task<Void, Never>?
    }
}
