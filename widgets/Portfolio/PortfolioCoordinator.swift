import Foundation
import Observation
import Portfolio

/// Owns one presentation's portfolio work and publishes state on the main actor.
///
/// Inject a service bound to the selected network; create a new coordinator when
/// changing networks. The service continues to own caching, pricing, and subscriptions.
@MainActor
@Observable
final class PortfolioCoordinator: PortfolioCoordinating {
    private(set) var update: Update?

    private let service: any PortfolioProviding
    @ObservationIgnored private var owner: String?
    @ObservationIgnored private var session: UUID?
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var observationState: (phase: Update.Phase, revision: UInt64)?
    @ObservationIgnored private var refreshID: UUID?
    @ObservationIgnored private var reloading: Task<Void, Never>?

    /// Creates presentation coordination around an interchangeable portfolio service.
    /// - Parameter service: The portfolio provider for one configured network.
    init(service: any PortfolioProviding) {
        self.service = service
    }

    /// Replaces the active wallet session and runs until the view task is cancelled.
    /// - Parameters:
    ///   - owner: The selected public wallet address, or `nil` to clear selection.
    ///   - isActive: Whether the presenting scene is active.
    func observe(for owner: String?, isActive: Bool) async {
        guard !Task.isCancelled else { return }
        if let session { stop(session: session) }
        if self.owner != owner { update = nil }
        self.owner = owner
        guard isActive, let owner else { return }

        let session = UUID()
        self.session = session
        let service = service
        let operation = Task { @concurrent [weak self] in
            guard !Task.isCancelled else { return }
            let updates = await service.observations(for: owner)
            for await update in updates {
                guard !Task.isCancelled else { return }
                await self?.receive(update, session: session, fromObservation: true)
            }
            // A disconnected stream must not reconnect automatically. Keep the
            // view's cancellation boundary alive so explicit refresh still works.
            let lifetime = AsyncStream<Never> { _ in }
            for await _ in lifetime {}
        }
        observation = operation
        await withTaskCancellationHandler {
            await operation.value
        } onCancel: { [weak self] in
            operation.cancel()
            Task { @MainActor [weak self] in self?.stop(session: session) }
        }
        stop(session: session)
    }

    /// Forces one reload for the active wallet without restarting its subscription.
    func refresh() async {
        guard !Task.isCancelled, let session, let owner else { return }
        let id: UUID
        let operation: Task<Void, Never>
        if let refreshID, let reloading {
            id = refreshID
            operation = reloading
        } else {
            id = UUID()
            let service = service
            operation = Task { @concurrent [weak self] in
                guard !Task.isCancelled else { return }
                let updates = await service.updates(for: owner, policy: .reload)
                for await update in updates {
                    guard !Task.isCancelled else { return }
                    await self?.receive(update, session: session, fromObservation: false)
                }
            }
            refreshID = id
            reloading = operation
        }
        await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
        }
        guard self.session == session, refreshID == id else { return }
        refreshID = nil
        reloading = nil
        if operation.isCancelled, update?.isRefreshing == true {
            if let observationState {
                setPhase(observationState.phase)
            } else {
                settleProgress()
            }
        }
    }

    /// Publishes only the current session's results, retaining the newest complete data.
    /// - Parameters:
    ///   - incoming: A state from observation or an explicit refresh.
    ///   - session: The view lifetime that requested this state.
    ///   - fromObservation: Whether this state also describes the ongoing observation.
    private func receive(_ incoming: Update, session: UUID, fromObservation: Bool) {
        guard !Task.isCancelled, self.session == session,
              incoming.snapshot.map({ $0.owner == owner }) ?? true else { return }
        if fromObservation, observationState.map({ incoming.revision > $0.revision }) ?? true {
            observationState = (incoming.phase, incoming.revision)
        }
        guard let current = update else { update = incoming; return }
        // Replaying the same provider state restores progress settled locally on cancellation.
        let acceptsPhase = incoming.revision >= current.revision
        let newerSnapshot: Bool
        if let revision = incoming.snapshotRevision {
            newerSnapshot = current.snapshotRevision.map { revision > $0 } ?? true
        } else {
            newerSnapshot = false
        }
        guard acceptsPhase || newerSnapshot else { return }
        update = Update(snapshot: newerSnapshot ? incoming.snapshot : current.snapshot,
                        phase: acceptsPhase ? incoming.phase : current.phase,
                        revision: max(incoming.revision, current.revision),
                        snapshotRevision: newerSnapshot ? incoming.snapshotRevision : current.snapshotRevision)
    }

    /// Cancels a departing session without allowing old cleanup to stop its replacement.
    /// - Parameter session: The lifetime that must still own the current work.
    private func stop(session: UUID) {
        guard self.session == session else { return }
        self.session = nil
        observation?.cancel()
        observation = nil
        observationState = nil
        reloading?.cancel()
        reloading = nil
        refreshID = nil
        settleProgress()
    }

    /// Removes cancelled progress while preserving completed holdings and reported errors.
    private func settleProgress() {
        guard update?.isRefreshing == true else { return }
        if update?.snapshot == nil { update = nil } else { setPhase(.ready) }
    }

    /// Changes local progress without inventing a newer provider result.
    /// - Parameter phase: The restored observation status or settled local progress.
    private func setPhase(_ phase: Update.Phase) {
        guard let update else { return }
        self.update = Update(snapshot: update.snapshot, phase: phase, revision: update.revision,
                             snapshotRevision: update.snapshotRevision)
    }
}
