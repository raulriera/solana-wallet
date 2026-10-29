import Foundation
import Observation
import RPC
import Wallet

/// One account's private balance on one network, which every window that observes the account there shares.
///
/// The first observer starts one poll loop and the last one ends it, keeping the balance for the next window. The loop
/// reads the balance, then polls it, and starts again after each of the account's private moves on the network settles;
/// payments never change the private balance, so they start nothing. Callers that read while a read runs share it. A
/// read shows the account's last read balance, or why it has none; a failed read keeps what was read before, or shows
/// the balance that the account's saved notes hold, and marks it outdated until a read succeeds. Unless a read found
/// private balances off or unavailable, a poll reads the balance again; a failure that reading again can't fix, such
/// as a rate limit, pauses polling until a refresh succeeds. When a read after one of the account's private moves
/// settles finds pending SOL, the next few polls follow up quickly until the indexer reports it. Accounts whose path
/// has no private-balance keys show nothing.
@MainActor
@Observable
final class WalletPrivateBalance {
    /// The account's last read balance, or why it has none; `nil` before the first read, or for an account without
    /// private-balance keys.
    private(set) var status: PrivateBalanceStatus? {
        didSet { hasBalance = Self.holdsSOL(status) }
    }
    /// Whether the account holds any private SOL, available or pending; kept apart from ``status`` so the token list
    /// changes only when this does.
    private(set) var hasBalance = false
    /// Whether the last read failed, so ``status`` is what an earlier read found or the saved notes hold, if anything.
    private(set) var isOutdated = false
    /// Whether polls wait for a refresh, after a failure that reading again can't fix.
    private(set) var isPollingPaused = false
    /// The quick reads left until the pending SOL of a settled transaction turns available.
    private(set) var followUpReadsLeft = 0

    /// The account whose balance this is.
    private let account: Account
    /// The network that the balance belongs to.
    private let network: Network
    private let balances: any PrivateBalancing
    private let transactions: TransactionStore
    private let pollInterval: Duration
    private let followUpInterval: Duration
    /// When the last read that succeeded started, or `nil` before the first read.
    @ObservationIgnored private var lastReadStarted: Date?
    /// The read that's running, which every caller of ``refresh()`` meanwhile shares.
    @ObservationIgnored private var reading: Task<Void, Never>?
    /// The callers of ``observe()`` that are running.
    @ObservationIgnored private var observers = 0
    /// Starts the poll loop again after each settled private move, while the balance has observers.
    @ObservationIgnored private var watching: Task<Void, Never>?
    /// The read and poll loop, which runs while the balance has observers.
    @ObservationIgnored private var polling: Task<Void, Never>?

    /// Whether polls follow up quickly on pending SOL from a settled transaction.
    var isFollowingUp: Bool { followUpReadsLeft > 0 }

    /// The account's available private SOL, in lamports, or `nil` while it has none to move.
    var availableLamports: UInt64? {
        guard case .balance(let available, _)? = status, available > 0 else { return nil }
        return available
    }

    /// The account's private move on the network that settled last; each one reads the balance again.
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

    /// The quick reads that follow a settled transaction with pending SOL, at most.
    static let followUpReads = 10

    /// Creates a balance that shows nothing until its first read.
    /// - Parameters:
    ///   - account: The account whose balance this is.
    ///   - network: The network that the balance belongs to.
    ///   - balances: The private balances of every account.
    ///   - transactions: The transactions whose settled private moves read the balance again.
    ///   - pollInterval: The time between polls.
    ///   - followUpInterval: The time between polls that follow up on pending SOL.
    init(account: Account, network: Network, balances: any PrivateBalancing, transactions: TransactionStore,
         pollInterval: Duration, followUpInterval: Duration) {
        self.account = account
        self.network = network
        self.balances = balances
        self.transactions = transactions
        self.pollInterval = pollInterval
        self.followUpInterval = followUpInterval
    }

    /// Reads and polls the balance until the calling task is cancelled, sharing one poll loop with the other observers.
    func observe() async {
        guard !Task.isCancelled else { return }
        observers += 1
        if observers == 1 { start() }
        // Each observer holds the shared loop until its own task ends.
        let lifetime = AsyncStream<Never> { _ in }
        for await _ in lifetime {}
        observers -= 1
        if observers == 0 { stop() }
    }

    /// Reads and polls the balance again, as after a provider change, while it has observers.
    func observeAgain() {
        guard observers > 0 else { return }
        startPolling()
    }

    /// Reads the balance again, or waits for the read that's running; a failed read keeps the balance read before.
    ///
    /// A failure that reading again can't fix, such as a rate limit or a rejected key, pauses polling; a read that
    /// succeeds resumes it. The first read that finds pending SOL after one of the account's private moves settled
    /// starts a follow-up, and a read that finds nothing pending ends it.
    func refresh() async {
        guard account.path.hasPrivateBalanceKeys else { return }
        if let reading { return await reading.value }
        let read = Task {
            await self.read()
            // Callers that resume after the read must start their own, so the read ends itself.
            reading = nil
        }
        reading = read
        await read.value
    }

    /// Reads the balance again unless a read found private balances off or unavailable, or polling is paused; each poll
    /// uses one quick read of a follow-up.
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

    /// Reads the balance once the account's last settled private move has settled, which records the move in the
    /// account's notes, so the read never finds the balance from before the move.
    ///
    /// A read that's running may have started before the move settled or through a previous provider, so this one
    /// starts after it ends.
    func readAfterSettling() async {
        await transactions.load(key)
        if let move = lastSettledMove {
            // The move's watch ends once its settling ran; a watch error leaves nothing more to wait for.
            _ = try? await transactions.watch(move.id, for: key)
        }
        await reading?.value
        // A cancelled loop's replacement reads the balance itself.
        guard !Task.isCancelled else { return }
        await refresh()
    }

    /// Turns private balances on for the account, then reads its balance.
    /// - Throws: `CancellationError` when the person cancels authentication, or the error of turning on or reading.
    func turnOn() async throws {
        try await balances.enable(account, on: network)
        let settled = lastSettledMove?.settled
        let started = Date.now
        receive(try await balances.refresh(account, on: network), settled: settled, started: started)
    }

    /// Ends the poll loop and the running read, and forgets the balance, as Reset App does.
    func erase() {
        stop()
        reading?.cancel()
        reading = nil
        lastReadStarted = nil
        status = nil
        isOutdated = false
    }

    /// The account's records on the network.
    private var key: TransactionRecord.Key {
        TransactionRecord.Key(account: account.id, network: network)
    }

    /// Starts the poll loop, and starts it again after each private move that settles while the balance has observers.
    private func start() {
        let transactions = transactions
        let key = key
        watching = Task { [weak self] in
            // The records are read first, so a move that settled before this observation starts the loop once.
            await transactions.load(key)
            let moves = Observations { [weak self] in self?.lastSettledMove?.id }
            var polledMove: TransactionRecord.ID??
            // A record change that keeps the last settled move, such as a new payment, reads nothing.
            for await move in moves where move != polledMove {
                guard let self, !Task.isCancelled else { return }
                polledMove = move
                startPolling()
            }
        }
    }

    /// Starts the poll loop again: a read after the last settled move, then a poll after each interval.
    private func startPolling() {
        polling?.cancel()
        polling = Task { [weak self, pollInterval, followUpInterval] in
            await self?.readAfterSettling()
            // Each wait ends early, and polling stops, once the loop is cancelled; waits don't keep the balance.
            while let interval = self.map({ $0.isFollowingUp ? followUpInterval : pollInterval }),
                  (try? await Task.sleep(for: interval)) != nil {
                await self?.poll()
            }
        }
    }

    /// Ends the poll loop and its restarts, keeping the balance.
    private func stop() {
        watching?.cancel()
        watching = nil
        polling?.cancel()
        polling = nil
    }

    /// Reads the balance once; a failed read marks the balance outdated, and shows the saved one if none shows yet.
    private func read() async {
        let settled = lastSettledMove?.settled
        let started = Date.now
        do {
            let status = try await balances.refresh(account, on: network)
            // An erased balance keeps nothing that a read finds.
            guard !Task.isCancelled else { return }
            receive(status, settled: settled, started: started)
        } catch {
            guard !Task.isCancelled, !isStale(started) else { return }
            guard !(error is CancellationError) else {
                isPollingPaused = false
                return
            }
            isPollingPaused = (error as? RPCError)?.isRecoverable != true
            // Keys that another app registered aren't an outdated balance; nothing shows for them, as before.
            guard !(error is PrivateBalanceError) else { return }
            if status == nil {
                // Saved notes that can't be read leave nothing to show but the outdated mark. A newer read that
                // succeeds meanwhile sets the status and stays current.
                let saved = try? await balances.savedStatus(of: account, on: network)
                guard !Task.isCancelled, status == nil else { return }
                status = saved
            }
            // Set with the saved balance in one update, so the footer never shows alone before the balance.
            isOutdated = true
        }
    }

    /// Shows a read balance as current, resumes polling, and starts or ends a follow-up on its pending SOL.
    /// - Parameters:
    ///   - status: The read balance.
    ///   - settled: When the account's last private move settled before the read, or `nil` without one.
    ///   - started: When the read started.
    private func receive(_ status: PrivateBalanceStatus, settled: Date?, started: Date) {
        guard !isStale(started) else { return }
        self.status = status
        isOutdated = false
        isPollingPaused = false
        // A move that settled while the last read ran may be missing from that read, so it counts as new.
        let settledSinceRead = if let lastReadStarted, let settled { settled > lastReadStarted } else { false }
        lastReadStarted = started
        guard case .balance(_, let pending) = status, pending > 0 else {
            // Nothing left to turn available, so polls slow down again.
            followUpReadsLeft = 0
            return
        }
        if settledSinceRead { followUpReadsLeft = Self.followUpReads }
    }

    /// Whether a read started before the last read that succeeded, such as a poll that overlapped turning on, so its
    /// outcome is older than what shows.
    /// - Parameter started: When the read started.
    /// - Returns: Whether the read's outcome must be dropped.
    private func isStale(_ started: Date) -> Bool {
        guard let lastReadStarted else { return false }
        return started < lastReadStarted
    }

    /// Whether a status holds any private SOL.
    /// - Parameter status: A read status, or `nil` before the first read.
    /// - Returns: Whether the balance's available or pending SOL is above zero.
    private static func holdsSOL(_ status: PrivateBalanceStatus?) -> Bool {
        guard case .balance(let available, let pending) = status else { return false }
        return available > 0 || pending > 0
    }
}
