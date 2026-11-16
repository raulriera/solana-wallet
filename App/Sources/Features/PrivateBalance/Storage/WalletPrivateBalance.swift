import Algorithms
import Foundation
import Observation
import Privacy
import RPC
import Transactions
import Wallet

/// An account's private balance on a network, read and polled while it has observers.
@MainActor
@Observable
final class WalletPrivateBalance {
    /// The last read balance, or `nil` before the first read.
    private(set) var status: PrivateBalanceStatus? {
        didSet {
            privateHoldings = if case .balance(let balances)? = status { Set(balances.assets.map(\.asset)) } else { [] }
        }
    }
    /// The assets that the account holds an available or pending private amount of.
    private(set) var privateHoldings: Set<Asset.ID> = []
    /// Whether the last read failed.
    private(set) var isStale = false
    /// Whether polls wait for a refresh after a failure that reading again can't fix.
    private(set) var isPollingPaused = false
    /// The quick reads left in a follow-up on pending assets.
    private(set) var followUpReadsLeft = 0

    private let account: Account
    private let network: Network
    private let balances: any PrivateBalancing
    private let transactions: TransactionStore
    private let clock: any Clock<Duration>
    /// When the last successful read started, or `nil` before one.
    @ObservationIgnored private var lastReadStarted: Date?
    /// The running read, or `nil` when none runs.
    @ObservationIgnored private var reading: Task<Void, Never>?
    /// The number of running ``observe()`` calls.
    @ObservationIgnored private var observers = 0
    /// The task that restarts the poll loop after each settled private move.
    @ObservationIgnored private var watching: Task<Void, Never>?
    /// The read and poll loop.
    @ObservationIgnored private var polling: Task<Void, Never>?

    var isFollowingUp: Bool { followUpReadsLeft > 0 }

    /// Returns the available private amount of an asset.
    ///
    /// - Parameter asset: The asset.
    /// - Returns: The available amount, in the asset's smallest unit, or `nil` when there's none.
    func available(of asset: PrivateAsset) -> UInt64? {
        guard let available = status?.balance(of: asset)?.available, available > 0 else { return nil }
        return available
    }

    /// The account's private move on the network that settled last.
    var lastSettledMove: TransactionRecord? {
        transactions.records(for: key).lazy
            .filter { record in
                switch record.kind {
                case .privateDeposit, .privateWithdrawal: record.settled != nil
                case .payment: false
                }
            }
            .max { ($0.settled ?? .distantPast) < ($1.settled ?? .distantPast) }
    }

    /// The most quick reads that follow up on pending assets.
    private static let followUpReads = 10

    private static let pollInterval = Duration.seconds(30)
    private static let followUpInterval = Duration.seconds(3)

    /// Creates a balance with no status.
    ///
    /// - Parameters:
    ///   - account: The account whose balance this is.
    ///   - network: The network that the balance belongs to.
    ///   - balances: The private balances of every account.
    ///   - transactions: The transaction store.
    ///   - clock: The clock that times polls.
    init(account: Account, network: Network, balances: any PrivateBalancing, transactions: TransactionStore,
         clock: any Clock<Duration>) {
        self.account = account
        self.network = network
        self.balances = balances
        self.transactions = transactions
        self.clock = clock
    }

    /// Reads and polls the balance until the calling task is cancelled.
    func observe() async {
        guard !Task.isCancelled else { return }
        observers += 1
        if observers == 1 { start() }
        let lifetime = AsyncStream<Never> { _ in }
        for await _ in lifetime {}
        observers -= 1
        if observers == 0 { stop() }
    }

    /// Restarts reading and polling the balance while it has observers.
    func observeAgain() {
        guard observers > 0 else { return }
        startPolling()
    }

    /// Reads the balance again, or waits for the read that's running.
    func refresh() async {
        guard account.path.hasPrivateBalanceKeys else { return }
        if let reading { return await reading.value }
        let read = Task {
            await self.read()
            reading = nil
        }
        reading = read
        await read.value
    }

    /// Reads the balance again unless private balances are off or unavailable, or polling is paused.
    func poll() async {
        switch status {
        case .off?, .unavailable?:
            return
        case .unregistered?, .balance?, nil:
            guard !isPollingPaused else { return }
            if followUpReadsLeft > 0 { followUpReadsLeft -= 1 }
            await refresh()
        }
    }

    /// Reads the balance once the account's last private move finishes settling.
    func readAfterSettling() async {
        await transactions.load(key)
        if let move = lastSettledMove {
            _ = try? await transactions.watch(move.id, for: key)
        }
        await reading?.value
        guard !Task.isCancelled else { return }
        await refresh()
    }

    /// Turns private balances on for the account, then reads its balance.
    ///
    /// - Throws: `CancellationError` when the person cancels authentication, or the error of turning on or reading.
    func turnOn() async throws {
        try await balances.enable(account, on: network)
        let settled = lastSettledMove?.settled
        let started = Date.now
        receive(try await balances.refresh(account, on: network), settled: settled, started: started)
    }

    /// Ends the poll loop and the running read, and forgets the balance.
    func erase() {
        stop()
        reading?.cancel()
        reading = nil
        lastReadStarted = nil
        status = nil
        isStale = false
    }

    private var key: TransactionRecord.Key {
        TransactionRecord.Key(account: account.id, network: network)
    }

    /// Starts the poll loop, and restarts it after each settled private move.
    private func start() {
        let transactions = transactions
        let key = key
        watching = Task { [weak self] in
            await transactions.load(key)
            for await _ in Observations({ [weak self] in self?.lastSettledMove?.id }).removeDuplicates() {
                guard let self, !Task.isCancelled else { return }
                startPolling()
            }
        }
    }

    /// Restarts the loop that reads the balance and then polls it after each interval.
    private func startPolling() {
        polling?.cancel()
        polling = Task { [weak self, clock] in
            await self?.readAfterSettling()
            while let interval = self.map({ $0.isFollowingUp ? Self.followUpInterval : Self.pollInterval }),
                  (try? await clock.sleep(for: interval)) != nil {
                await self?.poll()
            }
        }
    }

    /// Ends the poll loop and its restarts.
    private func stop() {
        watching?.cancel()
        watching = nil
        polling?.cancel()
        polling = nil
    }

    /// Reads the balance once, marking it stale if the read fails.
    private func read() async {
        let settled = lastSettledMove?.settled
        let started = Date.now
        do {
            let status = try await balances.refresh(account, on: network)
            guard !Task.isCancelled else { return }
            receive(status, settled: settled, started: started)
        } catch {
            guard !Task.isCancelled, !isStale(started) else { return }
            guard !(error is CancellationError) else {
                isPollingPaused = false
                return
            }
            isPollingPaused = (error as? RPCError)?.isRecoverable != true
            guard !(error is PrivateBalanceError) else { return }
            if status == nil {
                let saved = try? await balances.savedStatus(of: account, on: network)
                guard !Task.isCancelled, status == nil else { return }
                status = saved
            }
            isStale = true
        }
    }

    /// Shows a read balance as current, resumes polling, and starts or ends a follow-up on its pending assets.
    ///
    /// - Parameters:
    ///   - status: The read balance.
    ///   - settled: When the account's last private move settled before the read, or `nil` without one.
    ///   - started: When the read started.
    private func receive(_ status: PrivateBalanceStatus, settled: Date?, started: Date) {
        guard !isStale(started) else { return }
        self.status = status
        isStale = false
        isPollingPaused = false
        let settledSinceRead = if let lastReadStarted, let settled { settled > lastReadStarted } else { false }
        lastReadStarted = started
        guard case .balance(let balances) = status, balances.hasPending else {
            followUpReadsLeft = 0
            return
        }
        if settledSinceRead { followUpReadsLeft = Self.followUpReads }
    }

    /// Returns whether a read started before the last successful read.
    ///
    /// - Parameter started: When the read started.
    /// - Returns: `true` if the read started before the last successful one.
    private func isStale(_ started: Date) -> Bool {
        guard let lastReadStarted else { return false }
        return started < lastReadStarted
    }
}
