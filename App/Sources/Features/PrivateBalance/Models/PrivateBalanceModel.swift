import Foundation
import Observation
import RPC
import Wallet

/// One window's private balance of its account on its network, turning private balances on for that account, and
/// opening moves of SOL between the account's balances.
///
/// A refresh shows the account's last read balance, or why it has none; a failed refresh keeps what was read before.
/// While private balances are on, a poll reads the balance again; a failure that reading again can't fix, such as a
/// rate limit, pauses polling until a refresh that the person or the window starts succeeds. After a transaction settles
/// with pending SOL, the next few polls follow up quickly until the indexer reports it. Accounts whose path has
/// no private-balance keys show nothing. Turning private balances on runs once per attempt in
/// the scene's task and reports a typed error, except when the person cancels authentication.
@MainActor
@Observable
final class PrivateBalanceModel {
    /// The account's last read balance, or why it has none; `nil` before the first read, or for an account without
    /// private-balance keys.
    private(set) var status: PrivateBalanceStatus? {
        didSet { hasBalance = Self.holdsSOL(status) }
    }
    /// Whether the account holds any private SOL, available or pending; kept apart from ``status`` so the token list
    /// changes only when this does.
    private(set) var hasBalance = false
    /// The error of the last attempt to turn private balances on, or to open a move.
    var error: PrivateBalanceError?
    /// The attempt to turn private balances on that's waiting for the scene's task, or running.
    private(set) var attempt: UUID?
    /// Whether the last attempt turned private balances on for the account.
    private(set) var isTurnedOn = false
    /// Whether polls wait for a refresh that the person or the window starts, after a failure that reading again
    /// can't fix.
    private(set) var isPollingPaused = false
    /// The open move of the account's SOL between its public and private balances.
    var move: BalanceMoveModel?
    /// Counts settled transactions that left pending SOL; each one starts the window's reads again.
    private(set) var followUp = 0
    /// The quick reads left until the pending SOL of a settled transaction turns available.
    private(set) var followUpReadsLeft = 0
    private var account: Account?
    private let balances: any PrivateBalancing
    private let transactions: TransactionStore
    private let network: Network

    /// Whether an attempt to turn private balances on is waiting or running.
    var isTurningOn: Bool { attempt != nil }

    /// Whether polls follow up quickly on pending SOL from a settled transaction.
    var isFollowingUp: Bool { followUpReadsLeft > 0 }

    /// The quick reads that follow a settled transaction with pending SOL, at most.
    static let followUpReads = 10

    /// Creates a model that shows nothing until its first refresh.
    /// - Parameters:
    ///   - balances: The private balances of every account.
    ///   - transactions: The transactions that every window sends, watches, and records.
    ///   - network: The window's network.
    init(balances: any PrivateBalancing, transactions: TransactionStore, network: Network) {
        self.balances = balances
        self.transactions = transactions
        self.network = network
    }

    /// Reads an account's private balance, starting over when the account differs from the last one.
    /// - Parameter account: The window's account.
    func refresh(for account: Account) async {
        if self.account != account {
            self.account = account
            status = nil
            error = nil
            attempt = nil
            isTurnedOn = false
            isPollingPaused = false
            move = nil
            followUpReadsLeft = 0
        }
        await refresh()
    }

    /// Reads the current account's private balance again; a failed read keeps the balance read before.
    ///
    /// A failure that reading again can't fix, such as a rate limit or a rejected key, pauses polling; a read that
    /// succeeds resumes it, and ends a follow-up once nothing is pending.
    func refresh() async {
        guard let account, account.path.hasPrivateBalanceKeys else { return }
        do {
            let status = try await balances.refresh(account, on: network)
            guard self.account == account else { return }
            self.status = status
            isPollingPaused = false
            // Nothing left to turn available, so polls slow down again.
            if case .balance(_, let pending) = status, pending > 0 { return }
            followUpReadsLeft = 0
        } catch {
            guard self.account == account else { return }
            isPollingPaused = !(error is CancellationError || (error as? RPCError)?.isRecoverable == true)
        }
    }

    /// Shows the balance that a settled transaction returned, such as a deposit's pending SOL, and follows up quickly
    /// until the indexer reports it.
    /// - Parameter status: The account's balance after the transaction settled.
    func show(_ status: PrivateBalanceStatus) {
        guard account != nil else { return }
        self.status = status
        guard case .balance(_, let pending) = status, pending > 0 else { return }
        followUpReadsLeft = Self.followUpReads
        followUp += 1
    }

    /// Reads the balance again while private balances are on for the account and polling isn't paused; each poll uses
    /// one quick read of a follow-up.
    func poll() async {
        switch status {
        case .unregistered?, .balance?:
            guard !isPollingPaused else { return }
            if followUpReadsLeft > 0 { followUpReadsLeft -= 1 }
            await refresh()
        case .off?, .unavailable?, nil:
            return
        }
    }

    /// Opens a deposit of the account's public SOL into its private balance, while private balances are on.
    /// - Parameter publicLamports: The account's public SOL, in lamports.
    func addToPrivateBalance(publicLamports: UInt64) {
        open(.toPrivate, spendableLamports: publicLamports)
    }

    /// The account's available private SOL, in lamports, or `nil` while it has none to move.
    var availableLamports: UInt64? {
        guard case .balance(let available, _)? = status, available > 0 else { return nil }
        return available
    }

    /// Opens a withdrawal of the account's available private SOL to its own public address, while it has some.
    func moveToPublicBalance() {
        guard let availableLamports else { return }
        open(.toPublic, spendableLamports: availableLamports)
    }

    /// Opens a move of the account's SOL between its balances, while private balances are on.
    /// - Parameters:
    ///   - direction: Which balance the SOL leaves, and which one it reaches.
    ///   - spendableLamports: The SOL that the move can take from the balance that it leaves, in lamports.
    private func open(_ direction: BalanceMoveModel.Direction, spendableLamports: UInt64) {
        guard let account, move == nil else { return }
        switch status {
        case .unregistered?, .balance?:
            do {
                move = BalanceMoveModel(direction: direction, account: account, network: network,
                                        spendableLamports: spendableLamports, balances: balances,
                                        coordinator: try transactions.coordinator(for: network),
                                        transactions: transactions)
            } catch {
                self.error = .preparationFailed
            }
        case .off?, .unavailable?, nil:
            return
        }
    }

    /// Asks to turn private balances on for the current account, unless an attempt is already waiting or running.
    func turnOn() {
        guard attempt == nil, account != nil else { return }
        error = nil
        attempt = UUID()
    }

    /// Turns private balances on once in the scene's SwiftUI-managed task, then reads the balance.
    /// - Parameter attempt: The identifier that the scene's task captured.
    func run(_ attempt: UUID?) async {
        guard let attempt, self.attempt == attempt, let account else { return }
        defer { if self.attempt == attempt { self.attempt = nil } }
        do {
            try await balances.enable(account, on: network)
            let status = try await balances.refresh(account, on: network)
            guard self.attempt == attempt, self.account == account else { return }
            self.status = status
            isTurnedOn = true
        } catch is CancellationError {
            // The person dismissed authentication, or the scene left.
        } catch {
            guard self.attempt == attempt else { return }
            self.error = error as? PrivateBalanceError ?? .turnOnFailed
        }
    }

    /// Whether a status holds any private SOL.
    /// - Parameter status: A read status, or `nil` before the first read.
    /// - Returns: Whether the balance's available or pending SOL is above zero.
    private static func holdsSOL(_ status: PrivateBalanceStatus?) -> Bool {
        guard case .balance(let available, let pending) = status else { return false }
        return available > 0 || pending > 0
    }
}
