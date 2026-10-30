import Foundation
import RPC
import Transactions

/// An actor that shares each wallet's finalized subscription and reloads its balances after finalized changes.
actor ObservationCoordinator {
    /// A cancellable wait of a given duration.
    typealias Pause = @Sendable (Duration) async throws -> Void

    private static let firstReconnectDelay = Duration.seconds(2)
    private static let longestReconnectDelay = Duration.seconds(60)

    private let refresh: RefreshCoordinator
    private let tokenLists: TokenListCoordinator
    private let changes: (any AccountChangeProviding)?
    private let pause: Pause
    private var watches: [String: Watch] = [:]

    /// Creates an observation coordinator.
    ///
    /// - Parameters:
    ///   - refresh: The refresh coordinator.
    ///   - tokenLists: The token lists whose accounts each subscription watches.
    ///   - changes: The provider of finalized account changes, or `nil` if none.
    ///   - pause: The cancellable wait for coalescing changes and spacing reconnections.
    init(refresh: RefreshCoordinator, tokenLists: TokenListCoordinator, changes: (any AccountChangeProviding)?,
         pause: @escaping Pause) {
        self.refresh = refresh
        self.tokenLists = tokenLists
        self.changes = changes
        self.pause = pause
    }

    /// Adds a consumer and starts or joins the wallet's observation.
    ///
    /// - Parameter owner: The wallet address.
    /// - Returns: Cached state, an initial reload, and refresh results after finalized changes.
    func observations(for owner: String) -> AsyncStream<Update> {
        guard !Task.isCancelled else { return AsyncStream { $0.finish() } }
        let unsubscribe: @Sendable (UUID) async -> Void = { id in await self.unsubscribe(owner: owner, id: id) }
        if var watch = watches[owner] {
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

    /// Watches an observed wallet's accounts again, then reads its balances once.
    ///
    /// - Parameter owner: The wallet address.
    func restart(for owner: String) {
        guard let watch = watches[owner] else { return }
        watch.connection?.cancel()
        watch.reconciliation?.cancel()
        connect(owner: owner, consumers: watch.consumers, latest: watch.latest, minContextSlot: watch.minContextSlot,
                reloads: watch.reloads)
    }

    /// Connects a wallet's disconnected observation again.
    ///
    /// - Parameter owner: The wallet address.
    func reconnect(for owner: String) {
        guard watches[owner]?.state == .disconnected else { return }
        restart(for: owner)
    }

    /// Reads an observed wallet again and waits for a read that starts after this call.
    ///
    /// - Parameter owner: The wallet address.
    func reload(for owner: String) async {
        guard let watch = watches[owner] else { return }
        switch watch.state {
        case .connected:
            watches[owner]?.reloadRequested = true
            schedule(owner: owner, generation: watch.generation, delayed: false)
        case .disconnected:
            restart(for: owner)
        case .connecting:
            break
        }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if watches[owner] == nil {
                    continuation.resume()
                } else {
                    watches[owner]?.reloads[id] = Reload(continuation: continuation)
                }
            }
        } onCancel: {
            Task { await self.endWait(id, owner: owner) }
        }
    }

    /// Cancels a wallet's observation and ends its consumers' streams.
    ///
    /// - Parameter owner: The wallet address.
    func stop(for owner: String) {
        guard let watch = watches.removeValue(forKey: owner) else { return }
        watch.connection?.cancel()
        watch.reconciliation?.cancel()
        watch.consumers.finish()
        for reload in watch.reloads.values { reload.continuation.resume() }
    }

    /// Watches every observed wallet's accounts again, then reads their balances once.
    func restartAll() {
        for owner in watches.keys { restart(for: owner) }
    }

    /// Cancels every wallet's observation and ends its consumers' streams.
    func stopAll() {
        for owner in watches.keys { stop(for: owner) }
    }

    /// Starts a new observation generation for a wallet's consumers.
    ///
    /// - Parameters:
    ///   - owner: The wallet address.
    ///   - consumers: The consumers' streams.
    ///   - latest: The newest update the consumers received, or `nil`.
    ///   - minContextSlot: The slot of the newest observed finalized change, or `nil`.
    ///   - reloads: The reloads waiting for a read.
    private func connect(owner: String, consumers: UpdateConsumers, latest: Update? = nil,
                         minContextSlot: UInt64? = nil, reloads: [UUID: Reload] = [:]) {
        let generation = UUID()
        watches[owner] = Watch(generation: generation, minContextSlot: minContextSlot, consumers: consumers, latest: latest,
                               reloads: reloads.mapValues { Reload(continuation: $0.continuation) })
        watches[owner]?.connection = Task { await listen(owner: owner, generation: generation) }
    }

    /// Watches the wallet for the observation's generation, reconnecting after each recoverable failure.
    ///
    /// - Parameters:
    ///   - owner: The wallet address.
    ///   - generation: The observation's generation.
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
                endWaits(of: owner) { _ in true }
                guard (error as? RPCError)?.isRecoverable == true,
                      await waitToReconnect(owner: owner, generation: generation) else {
                    return
                }
            }
        }
    }

    /// Subscribes to the wallet's account changes, then schedules a reload at once and after each change.
    ///
    /// - Parameters:
    ///   - owner: The wallet address.
    ///   - generation: The observation's generation.
    /// - Throws: The error that stopped or ended the subscriptions.
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
    ///
    /// - Parameters:
    ///   - owner: The wallet address.
    ///   - generation: The observation's generation.
    /// - Returns: Whether the observation connects again.
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

    /// Starts a reconciliation for the wallet unless one is running.
    ///
    /// - Parameters:
    ///   - owner: The wallet address.
    ///   - generation: The observation's generation.
    ///   - delayed: Whether to wait two seconds for nearby changes.
    private func schedule(owner: String, generation: UUID, delayed: Bool) {
        guard watches[owner]?.generation == generation, watches[owner]?.reconciliation == nil else { return }
        watches[owner]?.reconciliation = Task { await reconcile(owner: owner, generation: generation, delayed: delayed) }
    }

    /// Reloads the wallet's balances after an optional wait that gathers nearby changes.
    ///
    /// - Parameters:
    ///   - owner: The wallet address.
    ///   - generation: The observation's generation.
    ///   - delayed: Whether to wait for nearby changes first.
    private func reconcile(owner: String, generation: UUID, delayed: Bool) async {
        guard watches[owner]?.generation == generation else { return }
        watches[owner]?.reloadRequested = false
        let read = UUID()
        for (id, reload) in watches[owner]?.reloads ?? [:] where reload.read == nil {
            watches[owner]?.reloads[id]?.read = read
        }
        var handledRevision: UUID?
        var requestFailed = false
        defer {
            if let watch = watches[owner], watch.generation == generation {
                watches[owner]?.reconciliation = nil
                endWaits(of: owner) { $0.read == read }
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

    /// Sends a newer update from the current generation to the wallet's consumers.
    ///
    /// - Parameters:
    ///   - update: The update to send.
    ///   - owner: The wallet address.
    ///   - generation: The observation generation that produced the update.
    private func publish(_ update: Update, owner: String, generation: UUID) {
        guard watches[owner]?.generation == generation else { return }
        guard watches[owner]?.latest.map({ update.revision > $0.revision }) ?? true else { return }
        watches[owner]?.latest = update
        watches[owner]?.consumers.send(update)
    }

    /// Ends the waits of the matching reloads.
    ///
    /// - Parameters:
    ///   - owner: The wallet address.
    ///   - answered: Whether a reload's wait ends.
    private func endWaits(of owner: String, where answered: (Reload) -> Bool) {
        for (id, reload) in watches[owner]?.reloads ?? [:] where answered(reload) {
            watches[owner]?.reloads[id] = nil
            reload.continuation.resume()
        }
    }

    /// Ends a cancelled reload's wait.
    ///
    /// - Parameters:
    ///   - id: The reload's identifier.
    ///   - owner: The wallet address.
    private func endWait(_ id: UUID, owner: String) {
        watches[owner]?.reloads.removeValue(forKey: id)?.continuation.resume()
    }

    /// Removes a consumer and stops the observation when none remain.
    ///
    /// - Parameters:
    ///   - owner: The wallet address.
    ///   - id: The consumer's identifier.
    private func unsubscribe(owner: String, id: UUID) {
        watches[owner]?.consumers.remove(id)
        if watches[owner]?.consumers.isEmpty == true { stop(for: owner) }
    }

    /// A wallet's shared connection and its consumers' streams.
    private struct Watch {
        /// The progress of a watch's connection.
        enum State {
            case connecting
            case connected
            /// Waiting to reconnect, or stopped by an error.
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
        var reloads: [UUID: Reload] = [:]
    }

    /// A caller waiting for a reload, with the read that answers it.
    private struct Reload {
        let continuation: CheckedContinuation<Void, Never>
        var read: UUID?
    }
}
