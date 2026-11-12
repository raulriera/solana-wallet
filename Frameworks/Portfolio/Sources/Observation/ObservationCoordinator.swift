import Foundation
import RPC
import Transactions

/// An actor that shares each wallet's finalized subscription and reloads its balances after finalized changes.
actor ObservationCoordinator {
    /// How long a read after a change waits for nearby changes.
    private static let coalescingDelay = Duration.seconds(2)

    private let refresh: RefreshCoordinator
    private let tokenLists: TokenListCoordinator
    private let changes: (any AccountChangeProviding)?
    private let clock: any Clock<Duration>
    private var watches: [String: Watch] = [:]

    /// Creates an observation coordinator.
    ///
    /// - Parameters:
    ///   - refresh: The refresh coordinator.
    ///   - tokenLists: The token lists whose accounts each subscription watches.
    ///   - changes: The provider of finalized account changes, or `nil` if none.
    ///   - clock: The clock that times change coalescing and reconnection waits.
    init(refresh: RefreshCoordinator, tokenLists: TokenListCoordinator, changes: (any AccountChangeProviding)?,
         clock: any Clock<Duration>) {
        self.refresh = refresh
        self.tokenLists = tokenLists
        self.changes = changes
        self.clock = clock
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
                schedule(owner: owner, generation: watch.generation, after: .immediate)
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
        watch.reconciliation?.task.cancel()
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
            schedule(owner: owner, generation: watch.generation, after: .immediate)
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
        watch.reconciliation?.task.cancel()
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
                      await waitForBackoff(owner: owner, generation: generation) else {
                    return
                }
                watches[owner]?.state = .connecting
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
        schedule(owner: owner, generation: generation, after: .immediate)
        for try await slot in slots {
            try Task.checkCancellation()
            guard watches[owner]?.generation == generation else { return }
            watches[owner]?.revision = UUID()
            let minContextSlot = max(watches[owner]?.minContextSlot ?? 0, slot)
            watches[owner]?.minContextSlot = minContextSlot
            schedule(owner: owner, generation: generation, after: .coalescing)
        }
        try Task.checkCancellation()
        throw RPCError.transport(.networkConnectionLost)
    }

    /// Waits the reconnection delay and doubles it for the next attempt.
    ///
    /// - Parameters:
    ///   - owner: The wallet address.
    ///   - generation: The observation's generation.
    /// - Returns: Whether the observation's generation is still current after the wait.
    private func waitForBackoff(owner: String, generation: UUID) async -> Bool {
        guard !Task.isCancelled, watches[owner]?.generation == generation,
              let delay = watches[owner]?.backoff.next() else { return false }
        do {
            try await clock.sleep(for: delay)
        } catch {
            return false
        }
        return watches[owner]?.generation == generation
    }

    /// Starts a reconciliation for the wallet unless one is reading or is waiting no longer than this delay.
    ///
    /// - Parameters:
    ///   - owner: The wallet address.
    ///   - generation: The observation's generation.
    ///   - delay: The wait before the read.
    private func schedule(owner: String, generation: UUID, after delay: ReadDelay) {
        guard let watch = watches[owner], watch.generation == generation else { return }
        if let current = watch.reconciliation {
            guard let waiting = current.waiting, delay < waiting else { return }
            current.task.cancel()
        }
        let task = Task { await reconcile(owner: owner, generation: generation, after: delay) }
        watches[owner]?.reconciliation = Reconciliation(task: task, waiting: delay)
    }

    /// Reloads the wallet's balances after a wait, then schedules the read that the result calls for.
    ///
    /// - Parameters:
    ///   - owner: The wallet address.
    ///   - generation: The observation's generation.
    ///   - delay: The wait before the read.
    private func reconcile(owner: String, generation: UUID, after delay: ReadDelay) async {
        guard await wait(delay, owner: owner, generation: generation) else { return }
        watches[owner]?.reconciliation?.waiting = nil
        watches[owner]?.reloadRequested = false
        let read = UUID()
        for (id, reload) in watches[owner]?.reloads ?? [:] where reload.read == nil {
            watches[owner]?.reloads[id]?.read = read
        }
        let handledRevision = watches[owner]?.revision
        var readError: (any Error)?
        defer {
            finish(read, owner: owner, generation: generation, handledRevision: handledRevision, readError: readError)
        }
        do {
            let minContextSlot = watches[owner]?.minContextSlot
            for await update in await refresh.updates(for: owner, minContextSlot: minContextSlot) {
                try Task.checkCancellation()
                if case .ready = update.phase, let watch = watches[owner], watch.generation == generation,
                   watch.state == .connected {
                    watches[owner]?.backoff.reset()
                }
                publish(update, owner: owner, generation: generation)
                if case .failed(let error) = update.phase { readError = error }
            }
        } catch {
            readError = error
            guard !Task.isCancelled else { return }
            let failed = await refresh.status(for: owner, phase: .failed(error))
            publish(failed, owner: owner, generation: generation)
        }
    }

    /// Waits before a reconciliation's read.
    ///
    /// - Parameters:
    ///   - delay: How long to wait.
    ///   - owner: The wallet address.
    ///   - generation: The observation's generation.
    /// - Returns: Whether the reconciliation still reads: no shorter wait replaced it and its generation is current.
    private func wait(_ delay: ReadDelay, owner: String, generation: UUID) async -> Bool {
        switch delay {
        case .immediate:
            break
        case .coalescing:
            guard (try? await clock.sleep(for: Self.coalescingDelay)) != nil else { return false }
        case .backoff:
            guard await waitForBackoff(owner: owner, generation: generation) else { return false }
        }
        return !Task.isCancelled && watches[owner]?.generation == generation
    }

    /// Ends a reconciliation's reload waits, then schedules a read for a reload, a newer change, or a recoverable
    /// failure on a live connection.
    ///
    /// - Parameters:
    ///   - read: The identifier that marks the reloads this read answers.
    ///   - owner: The wallet address.
    ///   - generation: The observation's generation.
    ///   - handledRevision: The change revision the read handled.
    ///   - readError: The error that ended the read, or `nil` if it succeeded.
    private func finish(_ read: UUID, owner: String, generation: UUID, handledRevision: UUID?, readError: (any Error)?) {
        guard let watch = watches[owner], watch.generation == generation else { return }
        watches[owner]?.reconciliation = nil
        endWaits(of: owner) { $0.read == read }
        guard !Task.isCancelled else { return }
        if watch.reloadRequested {
            schedule(owner: owner, generation: generation, after: .immediate)
        } else if readError == nil, watch.revision != handledRevision {
            schedule(owner: owner, generation: generation, after: .coalescing)
        } else if watch.state == .connected, (readError as? RPCError)?.isRecoverable == true {
            schedule(owner: owner, generation: generation, after: .backoff)
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
        /// The wait before the next reconnection or retried read.
        var backoff = Backoff.reconnection
        var reloadRequested = false
        var revision = UUID()
        var minContextSlot: UInt64?
        var consumers: UpdateConsumers
        var latest: Update?
        var connection: Task<Void, Never>?
        var reconciliation: Reconciliation?
        var reloads: [UUID: Reload] = [:]
    }

    /// A wallet's balance read and the wait before it.
    private struct Reconciliation {
        let task: Task<Void, Never>
        /// The wait that hasn't ended, or `nil` once the read has started.
        var waiting: ReadDelay?
    }

    /// The wait before a reconciliation reads, from shortest to longest.
    private enum ReadDelay: Comparable {
        case immediate
        /// Two seconds that gather nearby changes.
        case coalescing
        /// The reconnection delay after a recoverable failure.
        case backoff
    }

    /// A caller waiting for a reload, with the read that answers it.
    private struct Reload {
        let continuation: CheckedContinuation<Void, Never>
        var read: UUID?
    }
}
