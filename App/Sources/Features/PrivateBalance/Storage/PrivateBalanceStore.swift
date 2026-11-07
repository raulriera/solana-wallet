import Foundation
import Observation
import RPC

/// Keeps each account's private balance on each network.
@MainActor
@Observable
final class PrivateBalanceStore: Erasable {
    private var balances: [Key: WalletPrivateBalance] = [:]
    private let privateBalances: any PrivateBalancing
    private let transactions: TransactionStore
    private let pollInterval: Duration
    private let followUpInterval: Duration

    /// Creates a store.
    ///
    /// - Parameters:
    ///   - balances: The private balances of every account.
    ///   - transactions: The transaction store.
    ///   - rpcStore: The provider settings.
    ///   - pollInterval: The time between polls.
    ///   - followUpInterval: The time between polls that follow up on pending SOL.
    init(balances: any PrivateBalancing, transactions: TransactionStore, rpcStore: RPCStore,
         pollInterval: Duration = .seconds(30), followUpInterval: Duration = .seconds(3)) {
        privateBalances = balances
        self.transactions = transactions
        self.pollInterval = pollInterval
        self.followUpInterval = followUpInterval
        Task { [weak self] in
            for await _ in Observations({ rpcStore.connection }).changes() {
                guard let self else { return }
                providerDidChange()
            }
        }
    }

    /// Returns an account's private balance on a network.
    ///
    /// - Parameters:
    ///   - account: The account whose balance to read.
    ///   - network: The network whose balance to read.
    /// - Returns: The balance, or `nil` before it's observed or read.
    func balance(for account: Account, on network: Network) -> WalletPrivateBalance? {
        balances[Key(account, on: network)]
    }

    /// Reads and polls an account's private balance on a network for the lifetime of the calling task.
    ///
    /// - Parameters:
    ///   - account: The account whose balance to observe.
    ///   - network: The network to observe the balance on.
    func observe(_ account: Account, on network: Network) async {
        guard !Task.isCancelled else { return }
        await shared(account, on: network).observe()
    }

    /// Reads an account's private balance again, or waits for the read that's running.
    ///
    /// - Parameters:
    ///   - account: The account whose balance to read.
    ///   - network: The network to read the balance on.
    func refresh(_ account: Account, on network: Network) async {
        await shared(account, on: network).refresh()
    }

    /// Turns private balances on for an account on a network, then reads its balance.
    ///
    /// - Parameters:
    ///   - account: The account to turn private balances on for.
    ///   - network: The network to turn them on for.
    /// - Throws: `CancellationError` when the person cancels authentication, or the error of turning on or reading.
    func turnOn(_ account: Account, on network: Network) async throws {
        try await shared(account, on: network).turnOn()
    }

    /// Creates a move of an account's SOL between its balances, while private balances are on.
    ///
    /// - Parameters:
    ///   - direction: Which balance the SOL leaves, and which one it reaches.
    ///   - publicLamports: The account's public SOL, in lamports.
    ///   - account: The account whose SOL moves.
    ///   - network: The network that the SOL moves on.
    /// - Returns: The move, or `nil` while private balances are off or unread, or without SOL to withdraw.
    func move(_ direction: BalanceMoveProposal.Direction, publicLamports: UInt64, for account: Account,
              on network: Network) -> BalanceMove? {
        guard let balance = balance(for: account, on: network) else { return nil }
        switch balance.status {
        case .unregistered?, .balance?:
            let spendable = switch direction {
            case .toPrivate: publicLamports
            case .toPublic: balance.availableLamports
            }
            guard let spendable else { return nil }
            return BalanceMove(direction: direction, account: account, network: network, spendableLamports: spendable,
                               balances: privateBalances, transactions: transactions)
        case .off?, .unavailable?, nil:
            return nil
        }
    }

    func erase() async throws {
        for balance in balances.values { balance.erase() }
        balances = [:]
    }

    /// Returns an account's balance on a network, creating it on the first request.
    ///
    /// - Parameters:
    ///   - account: The account whose balance it is.
    ///   - network: The network that the balance belongs to.
    /// - Returns: The account's balance on the network.
    private func shared(_ account: Account, on network: Network) -> WalletPrivateBalance {
        let key = Key(account, on: network)
        if let balance = balances[key] { return balance }
        let balance = WalletPrivateBalance(account: account, network: network, balances: privateBalances,
                                           transactions: transactions, pollInterval: pollInterval,
                                           followUpInterval: followUpInterval)
        balances[key] = balance
        return balance
    }

    /// Reads every observed balance again after a change to the provider connection.
    private func providerDidChange() {
        for balance in balances.values { balance.observeAgain() }
    }

    /// The identifier of an account's balance on a network.
    private struct Key: Hashable {
        let account: UUID
        let network: Network

        /// Creates the identifier of an account's balance on a network.
        ///
        /// - Parameters:
        ///   - account: The account whose balance it is.
        ///   - network: The network that the balance belongs to.
        init(_ account: Account, on network: Network) {
            self.account = account.id
            self.network = network
        }
    }
}
