import Foundation
import RPC

/// Shares a wallet's confirmed subscription and bounds event-driven DAS reconciliation.
actor ObservationCoordinator {
    /// Suspends coalescing or indexer catch-up for a cancellable duration.
    typealias Pause = @Sendable (Duration) async throws -> Void

    private let refresh: RefreshCoordinator
    private let changes: (any AccountChangeProviding)?
    private let network: Network
    private let pause: Pause
    private var watches: [String: Watch] = [:]

    /// Creates observation policy around the same refresh coordinator used by explicit requests.
    /// - Parameters:
    ///   - refresh: The owner of cache, in-flight refreshes, and pending indexing requirements.
    ///   - changes: The optional provider of confirmed wallet-change slots.
    ///   - network: The network whose portfolio is observed.
    ///   - pause: Cancellable scheduling for coalescing and indexer catch-up.
    init(refresh: RefreshCoordinator, changes: (any AccountChangeProviding)?, network: Network,
         pause: @escaping Pause) {
        self.refresh = refresh
        self.changes = changes
        self.network = network
        self.pause = pause
    }

    /// Registers a consumer before starting or joining the wallet's long-lived observation.
    /// - Parameter owner: The wallet whose holdings to observe.
    /// - Returns: Cached state, initial reload, and subsequent confirmed-change refresh results.
    func observations(for owner: String) -> AsyncStream<Update> {
        let (stream, continuation) = AsyncStream<Update>.makeStream(bufferingPolicy: .bufferingNewest(2))
        guard !Task.isCancelled else { continuation.finish(); return stream }
        let id = UUID()
        continuation.onTermination = { @Sendable _ in
            Task { @concurrent in await self.unsubscribe(owner: owner, id: id) }
        }
        if var watch = watches[owner] {
            watch.consumers[id] = continuation
            if let latest = watch.latest, latest.isRefreshing {
                continuation.yield(latest)
            } else if watch.isConnected {
                watch.reloadRequested = true
            }
            watches[owner] = watch
            if watch.reloadRequested { schedule(owner: owner, generation: watch.generation, delayed: false) }
        } else {
            let generation = UUID()
            watches[owner] = Watch(generation: generation, consumers: [id: continuation])
            watches[owner]?.connection = Task { await listen(owner: owner, generation: generation) }
        }
        return stream
    }

    /// Cancels this wallet's observation before its cache is removed.
    /// - Parameter owner: The wallet leaving the portfolio.
    func stop(for owner: String) {
        guard let watch = watches.removeValue(forKey: owner) else { return }
        watch.connection?.cancel()
        watch.reconciliation?.cancel()
        for consumer in watch.consumers.values { consumer.finish() }
    }

    /// Establishes subscriptions before requesting initial catch-up, avoiding the setup-to-fetch gap.
    /// - Parameters:
    ///   - owner: The watched wallet.
    ///   - generation: The observation lifetime, used to reject late work after cancellation.
    private func listen(owner: String, generation: UUID) async {
        let initial = await refresh.status(for: owner, phase: .refreshing)
        publish(initial, owner: owner, generation: generation)
        do {
            guard let changes else { throw ObservationError.providerUnavailable }
            guard changes.network == network else { throw ObservationError.networkMismatch }
            let slots = try await changes.changedSlots(for: owner)
            try Task.checkCancellation()
            guard watches[owner]?.generation == generation else { return }
            watches[owner]?.isConnected = true
            schedule(owner: owner, generation: generation, delayed: false)
            for try await slot in slots {
                try Task.checkCancellation()
                guard watches[owner]?.generation == generation else { return }
                await refresh.requireIndexedSlot(slot, for: owner)
                guard watches[owner]?.generation == generation else { return }
                watches[owner]?.revision = UUID()
                schedule(owner: owner, generation: generation, delayed: true)
            }
            try Task.checkCancellation()
            throw RPCError.transport(.networkConnectionLost)
        } catch {
            guard !Task.isCancelled, watches[owner]?.generation == generation else { return }
            let failed = await refresh.status(for: owner, phase: .failed(error))
            guard watches[owner]?.generation == generation else { return }
            publish(failed, owner: owner, generation: generation)
            stop(for: owner)
        }
    }

    /// Coalesces notifications into one active reconciliation task for this wallet.
    /// - Parameters:
    ///   - owner: The wallet to refresh.
    ///   - generation: The current observation lifetime.
    ///   - delayed: Whether to allow nearby events and the indexer two seconds to catch up.
    private func schedule(owner: String, generation: UUID, delayed: Bool) {
        guard watches[owner]?.generation == generation, watches[owner]?.reconciliation == nil else { return }
        watches[owner]?.reconciliation = Task { await reconcile(owner: owner, generation: generation, delayed: delayed) }
    }

    /// Retries only successful-but-behind DAS reads, at most three times per reconciliation cycle.
    /// - Parameters:
    ///   - owner: The wallet to reconcile.
    ///   - generation: The current observation lifetime.
    ///   - delayed: Whether to coalesce incoming changes before the first request.
    private func reconcile(owner: String, generation: UUID, delayed: Bool) async {
        guard watches[owner]?.generation == generation else { return }
        watches[owner]?.reloadRequested = false
        var handledRevision: UUID?
        var requestFailed = false
        defer {
            if let watch = watches[owner], watch.generation == generation {
                watches[owner]?.reconciliation = nil
                if !Task.isCancelled,
                   watch.reloadRequested || (!requestFailed && watch.revision != handledRevision) {
                    schedule(owner: owner, generation: generation, delayed: !watch.reloadRequested)
                }
            }
        }
        do {
            if delayed { try await pause(.seconds(2)) }
            for attempt in 0..<3 {
                try Task.checkCancellation()
                guard watches[owner]?.generation == generation else { return }
                handledRevision = watches[owner]?.revision
                let updates = await refresh.updates(for: owner, policy: .reload)
                var behind = false
                for await update in updates {
                    try Task.checkCancellation()
                    if case .indexingBehind = update.error as? ObservationError {
                        behind = true
                        if attempt < 2 { continue }
                    }
                    publish(update, owner: owner, generation: generation)
                    if update.error != nil && !behind { requestFailed = true; return }
                }
                try Task.checkCancellation()
                let stillPending = await refresh.hasPendingChanges(for: owner)
                if !behind && !stillPending { return }
                if attempt < 2 { try await pause(.seconds(2)) }
            }
        } catch {
            requestFailed = true
            guard !Task.isCancelled else { return }
            let failed = await refresh.status(for: owner, phase: .failed(error))
            publish(failed, owner: owner, generation: generation)
        }
    }

    /// Delivers complete presentation state only to the current observation generation.
    /// - Parameters:
    ///   - update: The cache or refresh result.
    ///   - owner: The observed wallet.
    ///   - generation: The observation lifetime that produced the result.
    private func publish(_ update: Update, owner: String, generation: UUID) {
        guard watches[owner]?.generation == generation else { return }
        guard watches[owner]?.latest.map({ update.revision > $0.revision }) ?? true else { return }
        watches[owner]?.latest = update
        for consumer in watches[owner]?.consumers.values ?? [:].values { consumer.yield(update) }
    }

    /// Releases the connection and active refresh when the final consumer leaves.
    /// - Parameters:
    ///   - owner: The observed wallet.
    ///   - id: The departing consumer.
    private func unsubscribe(owner: String, id: UUID) {
        watches[owner]?.consumers.removeValue(forKey: id)
        if watches[owner]?.consumers.isEmpty == true { stop(for: owner) }
    }

    /// One shared connection and its independent consumer streams.
    private struct Watch {
        let generation: UUID
        var isConnected = false
        var reloadRequested = false
        var revision = UUID()
        var consumers: [UUID: AsyncStream<Update>.Continuation]
        var latest: Update?
        var connection: Task<Void, Never>?
        var reconciliation: Task<Void, Never>?
    }
}
