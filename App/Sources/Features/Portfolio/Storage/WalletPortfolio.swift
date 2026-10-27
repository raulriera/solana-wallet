import Observation
import Portfolio

/// One wallet's portfolio on one network, which every window that observes the wallet there shares.
///
/// The first observer starts the wallet's observation and the last one ends it, settling any progress while keeping
/// the holdings for the next window. Reloads run through the observation, so every window receives their results.
@MainActor
@Observable
final class WalletPortfolio {
    /// The wallet's newest state, or `nil` before any data is available.
    private(set) var update: Update? {
        didSet {
            // Sort once per new snapshot, not for every phase change or view update.
            guard update?.snapshotRevision != oldValue?.snapshotRevision else { return }
            holdings = HoldingOrder.sorted(update?.holdings ?? [])
        }
    }

    /// The latest snapshot's holdings in display order, or none without a snapshot.
    private(set) var holdings: [Holding] = []

    /// The wallet's public address.
    private let owner: String
    private let service: PortfolioStore.Service
    /// The callers of ``observe()`` that are running.
    @ObservationIgnored private var observers = 0
    /// The wallet's observation, which runs while it has observers.
    @ObservationIgnored private var observation: Task<Void, Never>?

    /// Creates a portfolio with no data yet.
    /// - Parameters:
    ///   - owner: The wallet's public address.
    ///   - service: The service of the network that the portfolio belongs to.
    init(owner: String, service: PortfolioStore.Service) {
        self.owner = owner
        self.service = service
    }

    /// Observes the wallet until the calling task is cancelled, sharing one observation with the other observers.
    func observe() async {
        guard !Task.isCancelled else { return }
        observers += 1
        if observers == 1 { start() }
        // Each observer holds the shared observation until its own task ends.
        let lifetime = AsyncStream<Never> { _ in }
        for await _ in lifetime {}
        observers -= 1
        if observers == 0 { stop() }
    }

    /// Reads the observed wallet again, awaiting the read for pull-to-refresh.
    ///
    /// Every observer receives the results. Cancelling the caller stops its wait, not the read. A wallet that nothing
    /// observes isn't read.
    func refresh() async {
        guard observers > 0 else { return }
        await service.reload(for: owner)
    }

    /// Observes the wallet again, as after a provider change ended its observation, while it has observers.
    func observeAgain() {
        guard observers > 0 else { return }
        observation?.cancel()
        start()
    }

    /// Forgets the wallet's state, as Reset App does.
    func erase() {
        update = nil
    }

    /// Starts the wallet's observation, publishing each update in order.
    private func start() {
        let service = service
        let owner = owner
        observation = Task { @concurrent [weak self] in
            for await update in await service.observations(for: owner) {
                guard !Task.isCancelled else { return }
                await self?.receive(update)
            }
        }
    }

    /// Ends the wallet's observation and settles its progress, keeping its holdings.
    private func stop() {
        observation?.cancel()
        observation = nil
        guard update?.isRefreshing == true else { return }
        if let update, update.snapshot != nil {
            self.update = Update(snapshot: update.snapshot, phase: .ready, revision: update.revision,
                                 snapshotRevision: update.snapshotRevision)
        } else {
            update = nil
        }
    }

    /// Publishes an update of the running observation; the service sends the wallet's updates in order.
    /// - Parameter incoming: The service's state for the wallet.
    private func receive(_ incoming: Update) {
        // An ended observation's last update can still arrive; the observation that replaced it owns the state.
        guard !Task.isCancelled else { return }
        update = incoming
    }
}
