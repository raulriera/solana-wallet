import Foundation
import Observation
import Portfolio
import Transactions

/// Owns one presentation's portfolio work and publishes state on the main actor.
///
/// Inject a service bound to the selected network; create a new coordinator when
/// changing networks. The service continues to own caching, pricing, subscriptions, and token lists.
@MainActor
@Observable
final class PortfolioCoordinator: PortfolioCoordinating {
    private(set) var update: Update? {
        didSet {
            // Sort once per new snapshot, not for every phase change or view update.
            guard update?.snapshotRevision != oldValue?.snapshotRevision else { return }
            holdings = HoldingOrder.sorted(update?.holdings ?? [])
        }
    }

    private(set) var holdings: [Holding] = []

    /// The latest update's failure, classified without retaining the provider's error.
    var failure: PortfolioFailure? { update?.error.map(PortfolioFailure.init) }

    private let service: any PortfolioProviding & TokenListProviding
    @ObservationIgnored private var owner: String?
    @ObservationIgnored private var session: UUID?
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var observationState: (phase: Update.Phase, revision: UInt64)?
    @ObservationIgnored private var refreshID: UUID?
    @ObservationIgnored private var reloading: Task<Void, Never>?

    /// Creates presentation coordination around an interchangeable portfolio service.
    /// - Parameter service: The portfolio and token-list provider for one configured network.
    init(service: any PortfolioProviding & TokenListProviding) {
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

    /// Looks up a pasted mint address through the window's portfolio service.
    /// - Parameter mint: The pasted mint address.
    /// - Returns: The token with its on-chain name and symbol, and its logo when the provider has one.
    /// - Throws: `TokenLookupError` when the address isn't a fungible token mint, or a request error.
    func token(at mint: Address) async throws -> TokenPreview {
        try await service.token(at: mint)
    }

    /// Adds a token to the selected wallet's list; an observed wallet then reads its balances again.
    /// - Parameter token: A token that ``token(at:)`` found.
    /// - Throws: `TokenListError` for a full or unreadable list, or a file-system error if the list can't be saved.
    func add(_ token: ListedToken) async throws {
        guard let owner else { return }
        _ = try await service.addToken(token, for: owner)
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
