import Foundation
import RPC
import Transactions

/// Shares a wallet's finalized subscription and reloads its balances after finalized changes.
///
/// A dropped connection reconnects by itself, waiting longer after each attempt until a connection's balance read
/// succeeds. An error that a person must act on, such as a rate limit or a rejected key, keeps the consumers' streams
/// but waits for a person's reload, a token-list change, or a new consumer.
actor ObservationCoordinator {
    /// Suspends change coalescing or a reconnection for a cancellable duration.
    typealias Pause = @Sendable (Duration) async throws -> Void

    /// The wait before the first reconnection after a drop.
    private static let firstReconnectDelay = Duration.seconds(2)
    /// The longest wait between reconnections; each failed attempt doubles the wait up to this value.
    private static let longestReconnectDelay = Duration.seconds(60)

    private let refresh: RefreshCoordinator
    private let tokenLists: TokenListCoordinator
    private let changes: (any AccountChangeProviding)?
    private let pause: Pause
    private var watches: [String: Watch] = [:]

    /// Creates observation policy around the same refresh coordinator used by explicit requests.
    /// - Parameters:
    ///   - refresh: The owner of cache and in-flight refreshes.
    ///   - tokenLists: The token lists whose accounts each wallet's subscription watches.
    ///   - changes: The optional provider of finalized account-change slots on the observed network.
    ///   - pause: Cancellable scheduling for coalescing nearby changes and spacing reconnections.
    init(refresh: RefreshCoordinator, tokenLists: TokenListCoordinator, changes: (any AccountChangeProviding)?,
         pause: @escaping Pause) {
        self.refresh = refresh
        self.tokenLists = tokenLists
        self.changes = changes
        self.pause = pause
    }

    /// Registers a consumer before starting or joining the wallet's long-lived observation.
    ///
    /// Joining a disconnected observation connects it again at once.
    /// - Parameter owner: The wallet whose holdings to observe.
    /// - Returns: Cached state, initial reload, and subsequent finalized-change refresh results.
    func observations(for owner: String) -> AsyncStream<Update> {
        guard !Task.isCancelled else { return AsyncStream { $0.finish() } }
        let unsubscribe: @Sendable (UUID) async -> Void = { id in await self.unsubscribe(owner: owner, id: id) }
        if var watch = watches[owner] {
            // A refresh in progress reaches the new consumer at once; otherwise a live watch reads balances for it.
            let refreshing = watch.latest.flatMap { $0.isRefreshing ? $0 : nil }
            let stream = watch.consumers.add(first: refreshing, onEnd: unsubscribe)
            if refreshing == nil, watch.state == .connected {
                watch.reloadRequested = true
            }
            watches[owner] = watch
            if watch.state == .disconnected {
                restart(for: owner)
            } else if watch.reloadRequested {
                schedule(owner: owner, generation: watch.generation, delayed: false)
            }
            return stream
        }
        var consumers = UpdateConsumers()
        let stream = consumers.add(onEnd: unsubscribe)
        connect(owner: owner, consumers: consumers)
        return stream
    }

    /// Watches an observed wallet's accounts again after its token list changes, then reads its balances once.
    ///
    /// Consumers keep their streams. A wallet that isn't observed is left alone.
    /// - Parameter owner: The wallet whose token list changed.
    func restart(for owner: String) {
        guard let watch = watches[owner] else { return }
        watch.connection?.cancel()
        watch.reconciliation?.cancel()
        connect(owner: owner, consumers: watch.consumers, latest: watch.latest, minContextSlot: watch.minContextSlot)
    }

    /// Connects a disconnected observation again at once, so a person's reload also restores live updates.
    ///
    /// An observation that is connected or connecting is left alone, as is a wallet that isn't observed.
    /// - Parameter owner: The wallet that a person reloads.
    func reconnect(for owner: String) {
        guard watches[owner]?.state == .disconnected else { return }
        restart(for: owner)
    }

    /// Cancels this wallet's observation before its cache is removed.
    /// - Parameter owner: The wallet leaving the portfolio.
    func stop(for owner: String) {
        guard let watch = watches.removeValue(forKey: owner) else { return }
        watch.connection?.cancel()
        watch.reconciliation?.cancel()
        watch.consumers.finish()
    }

    /// Cancels every wallet's observation and ends its consumers' streams.
    func stopAll() {
        for owner in watches.keys { stop(for: owner) }
    }

    /// Starts a new observation lifetime for a wallet's consumers, so earlier work can't deliver results.
    /// - Parameters:
    ///   - owner: The watched wallet.
    ///   - consumers: The streams that receive the wallet's updates.
    ///   - latest: The newest update those consumers already received, if any.
    ///   - minContextSlot: The newest finalized change already observed, if any.
    private func connect(owner: String, consumers: UpdateConsumers, latest: Update? = nil,
                         minContextSlot: UInt64? = nil) {
        let generation = UUID()
        watches[owner] = Watch(generation: generation, minContextSlot: minContextSlot, consumers: consumers, latest: latest)
        watches[owner]?.connection = Task { await listen(owner: owner, generation: generation) }
    }

    /// Watches the wallet for the observation's lifetime, reconnecting after each dropped connection.
    ///
    /// Each failure shows its error at once. After a failure that `RPCError.isRecoverable` accepts, the watch
    /// waits the reconnection delay and connects again. Other errors leave the watch disconnected. The delay starts
    /// over once a connection's balance read succeeds, not when its subscription is acknowledged.
    /// - Parameters:
    ///   - owner: The watched wallet.
    ///   - generation: The observation lifetime, used to reject late work after cancellation.
    private func listen(owner: String, generation: UUID) async {
        let initial = await refresh.status(for: owner, phase: .refreshing)
        publish(initial, owner: owner, generation: generation)
        while true {
            do {
                try await watchChanges(owner: owner, generation: generation)
                return
            } catch {
                guard !Task.isCancelled, watches[owner]?.generation == generation else { return }
                watches[owner]?.state = .disconnected
                let failed = await refresh.status(for: owner, phase: .failed(error))
                guard watches[owner]?.generation == generation else { return }
                publish(failed, owner: owner, generation: generation)
                guard (error as? RPCError)?.isRecoverable == true,
                      await waitToReconnect(owner: owner, generation: generation) else {
                    return
                }
            }
        }
    }

    /// Establishes subscriptions before requesting initial catch-up, avoiding the setup-to-fetch gap.
    /// - Parameters:
    ///   - owner: The watched wallet.
    ///   - generation: The observation lifetime, used to reject late work after cancellation.
    /// - Throws: Why the subscriptions couldn't start or ended; a stream that ends counts as a lost connection.
    private func watchChanges(owner: String, generation: UUID) async throws {
        guard let changes else { throw ObservationError.providerUnavailable }
        let accounts = try await tokenLists.list(for: owner).accounts(of: Address(owner))
        let slots = try await changes.changedSlots(for: accounts.map(\.value))
        try Task.checkCancellation()
        guard watches[owner]?.generation == generation else { return }
        watches[owner]?.state = .connected
        schedule(owner: owner, generation: generation, delayed: false)
        for try await slot in slots {
            try Task.checkCancellation()
            guard watches[owner]?.generation == generation else { return }
            watches[owner]?.revision = UUID()
            let minContextSlot = max(watches[owner]?.minContextSlot ?? 0, slot)
            watches[owner]?.minContextSlot = minContextSlot
            schedule(owner: owner, generation: generation, delayed: true)
        }
        try Task.checkCancellation()
        throw RPCError.transport(.networkConnectionLost)
    }

    /// Waits the reconnection delay and doubles it for the next attempt.
    /// - Parameters:
    ///   - owner: The disconnected wallet.
    ///   - generation: The observation lifetime, used to reject late work after cancellation.
    /// - Returns: Whether this observation lifetime connects again.
    private func waitToReconnect(owner: String, generation: UUID) async -> Bool {
        guard let watch = watches[owner], watch.generation == generation else { return false }
        watches[owner]?.reconnectDelay = min(watch.reconnectDelay * 2, Self.longestReconnectDelay)
        do {
            try await pause(watch.reconnectDelay)
        } catch {
            return false
        }
        guard watches[owner]?.generation == generation else { return false }
        watches[owner]?.state = .connecting
        return true
    }

    /// Coalesces notifications into one active reconciliation task for this wallet.
    /// - Parameters:
    ///   - owner: The wallet to refresh.
    ///   - generation: The current observation lifetime.
    ///   - delayed: Whether to wait two seconds for nearby changes.
    private func schedule(owner: String, generation: UUID, delayed: Bool) {
        guard watches[owner]?.generation == generation, watches[owner]?.reconciliation == nil else { return }
        watches[owner]?.reconciliation = Task { await reconcile(owner: owner, generation: generation, delayed: delayed) }
    }

    /// Reloads balances once per cycle, after an optional wait that gathers nearby changes.
    ///
    /// A change that arrives during a reload starts another cycle, so the latest change is always read.
    /// Failed requests aren't retried. A completed reload over a live connection resets the reconnection delay.
    /// - Parameters:
    ///   - owner: The wallet to reload.
    ///   - generation: The current observation lifetime.
    ///   - delayed: Whether to gather nearby changes before the request.
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
            try Task.checkCancellation()
            guard watches[owner]?.generation == generation else { return }
            handledRevision = watches[owner]?.revision
            let minContextSlot = watches[owner]?.minContextSlot
            for await update in await refresh.updates(for: owner, minContextSlot: minContextSlot) {
                try Task.checkCancellation()
                if case .ready = update.phase, let watch = watches[owner], watch.generation == generation,
                   watch.state == .connected {
                    // The connection works, so a later drop waits the shortest time again.
                    watches[owner]?.reconnectDelay = Self.firstReconnectDelay
                }
                publish(update, owner: owner, generation: generation)
                if update.error != nil { requestFailed = true }
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
        watches[owner]?.consumers.send(update)
    }

    /// Releases the connection and active refresh when the final consumer leaves.
    /// - Parameters:
    ///   - owner: The observed wallet.
    ///   - id: The departing consumer.
    private func unsubscribe(owner: String, id: UUID) {
        watches[owner]?.consumers.remove(id)
        if watches[owner]?.consumers.isEmpty == true { stop(for: owner) }
    }

    /// One shared connection and its independent consumer streams.
    private struct Watch {
        /// The progress of a watch's connection.
        enum State {
            /// Opening subscriptions.
            case connecting
            /// Subscriptions are live.
            case connected
            /// Waiting to reconnect after a drop, or stopped by an error that a person must act on.
            case disconnected
        }

        let generation: UUID
        var state = State.connecting
        var reconnectDelay = ObservationCoordinator.firstReconnectDelay
        var reloadRequested = false
        var revision = UUID()
        var minContextSlot: UInt64?
        var consumers: UpdateConsumers
        var latest: Update?
        var connection: Task<Void, Never>?
        var reconciliation: Task<Void, Never>?
    }
}
