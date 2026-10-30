import Observation
import Portfolio

/// One wallet's portfolio on one network.
@MainActor
@Observable
final class WalletPortfolio {
    /// The wallet's newest state, or `nil` before any data is available.
    private(set) var update: Update? {
        didSet {
            presentation = PortfolioPresentation(update)
            error = update?.error.map(PortfolioError.init)
            guard update?.snapshotRevision != oldValue?.snapshotRevision else { return }
            snapshotRevision = update?.snapshotRevision
            holdings = HoldingOrder.sorted(update?.holdings ?? [])
        }
    }

    private(set) var presentation = PortfolioPresentation.blank
    private(set) var error: PortfolioError?
    private(set) var snapshotRevision: UInt64?
    /// The latest snapshot's holdings in display order.
    private(set) var holdings: [Holding] = []

    /// The wallet's public address.
    private let owner: String
    private let service: PortfolioStore.Service
    /// The number of running ``observe()`` calls.
    @ObservationIgnored private var observers = 0
    @ObservationIgnored private var observation: Task<Void, Never>?

    /// Creates a portfolio with no data yet.
    ///
    /// - Parameters:
    ///   - owner: The wallet's public address.
    ///   - service: The portfolio service of the wallet's network.
    init(owner: String, service: PortfolioStore.Service) {
        self.owner = owner
        self.service = service
    }

    /// Observes the wallet until the calling task is cancelled.
    func observe() async {
        guard !Task.isCancelled else { return }
        observers += 1
        if observers == 1 { start() }
        let lifetime = AsyncStream<Never> { _ in }
        for await _ in lifetime {}
        observers -= 1
        if observers == 0 { stop() }
    }

    /// Reads the observed wallet again.
    func refresh() async {
        guard observers > 0 else { return }
        await service.reload(for: owner)
    }

    /// Restarts the wallet's observation while it has observers.
    func observeAgain() {
        guard observers > 0 else { return }
        observation?.cancel()
        start()
    }

    /// Forgets the wallet's state.
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

    /// Publishes an update of the running observation.
    ///
    /// - Parameter incoming: The wallet's new state.
    private func receive(_ incoming: Update) {
        guard !Task.isCancelled else { return }
        update = incoming
    }
}
