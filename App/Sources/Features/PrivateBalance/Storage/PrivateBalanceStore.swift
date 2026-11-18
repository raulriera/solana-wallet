import Foundation
import Observation
import Portfolio
import Privacy
import RPC
import Transactions

/// Keeps each account's private balance on each network.
@MainActor
@Observable
final class PrivateBalanceStore: Erasable, AccountObserving {
    private var balances: [Key: WalletPrivateBalance] = [:]
    private let privateBalances: any PrivateBalancing
    private let transactions: TransactionStore
    private let clock: any Clock<Duration>

    /// Creates a store.
    ///
    /// - Parameters:
    ///   - balances: The private balances of every account.
    ///   - transactions: The transaction store.
    ///   - rpcStore: The provider settings.
    ///   - clock: The clock that times polls.
    init(balances: any PrivateBalancing, transactions: TransactionStore, rpcStore: RPCStore,
         clock: any Clock<Duration> = ContinuousClock()) {
        privateBalances = balances
        self.transactions = transactions
        self.clock = clock
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

    /// Creates a move of a holding's asset between an account's balances, or to a recipient's private balance, while private balances are on.
    ///
    /// - Parameters:
    ///   - direction: Which balance the asset leaves, and which one it reaches.
    ///   - holding: The account's public holding of the asset.
    ///   - account: The account whose asset moves.
    ///   - network: The network that the asset moves on.
    /// - Returns: The move, or `nil` while private balances are off or unread, for another owner's holding or an
    ///   asset that private balances don't hold, or without a private amount to withdraw.
    func move(
        _ direction: BalanceMoveProposal.Direction,
        of holding: Holding,
        for account: Account,
        on network: Network
    ) -> BalanceMove? {
        guard let balance = balance(for: account, on: network), let publicBalance = holding.balance,
            let asset = PrivateAsset(holding.id)
        else { return nil }
        switch balance.status {
        case .unregistered?, .balance?:
            let amount =
                switch direction {
                case .toPrivate: publicBalance.amount
                case .toPublic, .toRecipient: balance.available(of: asset)
                }
            guard let amount,
                let token = PaymentToken(
                    holding: holding,
                    balance: TokenAmount(amount: amount, decimals: publicBalance.decimals),
                    price: nil
                )
            else { return nil }
            return BalanceMove(
                direction: direction,
                token: token,
                privateAsset: asset,
                account: account,
                network: network,
                balances: privateBalances,
                transactions: transactions
            )
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
                                           transactions: transactions, clock: clock)
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
