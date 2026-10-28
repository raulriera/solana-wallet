import Foundation
import Observation
import RPC

/// Keeps each account's private balance on each network, shared by every window that shows it.
///
/// Windows that show the same account on the same network share its ``WalletPrivateBalance``: one read and one poll
/// loop. After each new provider connection, every observed balance reads again through it.
@MainActor
@Observable
final class PrivateBalanceStore: Erasable {
    /// Each account's private balance on each network that a window observed or read, kept for the next window that
    /// shows it.
    private var balances: [Key: WalletPrivateBalance] = [:]
    private let privateBalances: any PrivateBalancing
    private let transactions: TransactionStore
    private let pollInterval: Duration
    private let followUpInterval: Duration
    /// The provider connection that the observed balances last read through, or `nil` until the provider settings
    /// are read and after they're erased.
    @ObservationIgnored private var connection: ProviderClient.Endpoint?

    /// Creates a store that reads nothing until a window observes an account.
    /// - Parameters:
    ///   - balances: The private balances of every account.
    ///   - transactions: The transactions whose settled private moves read a balance again, and which moves send.
    ///   - providers: The provider settings, whose new connections read every observed balance again.
    ///   - pollInterval: The time between polls.
    ///   - followUpInterval: The time between polls that follow up on pending SOL.
    init(balances: any PrivateBalancing, transactions: TransactionStore, providers: ProviderStore,
         pollInterval: Duration = .seconds(30), followUpInterval: Duration = .seconds(3)) {
        privateBalances = balances
        self.transactions = transactions
        self.pollInterval = pollInterval
        self.followUpInterval = followUpInterval
        watch(providers)
    }

    /// An account's private balance on a network.
    /// - Parameters:
    ///   - account: The account whose balance to read.
    ///   - network: The network whose balance to read.
    /// - Returns: The balance that every window showing the account on the network shares, or `nil` before any window
    ///   observes or reads it.
    func balance(for account: Account, on network: Network) -> WalletPrivateBalance? {
        balances[Key(account, on: network)]
    }

    /// Reads and polls an account's private balance on a network for the lifetime of the calling task.
    ///
    /// Callers that observe the same account on the same network, such as two windows, share one read and one poll
    /// loop, which reads again after each of the account's private moves on the network settles.
    /// - Parameters:
    ///   - account: The account whose balance to observe.
    ///   - network: The network to observe the balance on.
    func observe(_ account: Account, on network: Network) async {
        guard !Task.isCancelled else { return }
        await shared(account, on: network).observe()
    }

    /// Reads an account's private balance again, or waits for the read that's running, for pull-to-refresh and for
    /// SOL's details.
    /// - Parameters:
    ///   - account: The account whose balance to read.
    ///   - network: The network to read the balance on.
    func refresh(_ account: Account, on network: Network) async {
        await shared(account, on: network).refresh()
    }

    /// Turns private balances on for an account on a network, then reads its balance.
    /// - Parameters:
    ///   - account: The account to turn private balances on for.
    ///   - network: The network to turn them on for.
    /// - Throws: `CancellationError` when the person cancels authentication, or the error of turning on or reading.
    func turnOn(_ account: Account, on network: Network) async throws {
        try await shared(account, on: network).turnOn()
    }

    /// Creates a move of an account's SOL between its balances, while private balances are on.
    ///
    /// A deposit can take the account's public SOL; a withdrawal takes its available private SOL, so it needs some.
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

    /// Forgets every account's private balance, as Reset App does, so no window shows a deleted wallet's balance.
    func erase() async throws {
        for balance in balances.values { balance.erase() }
        balances = [:]
    }

    /// Returns an account's balance on a network, creating it on the first request.
    /// - Parameters:
    ///   - account: The account whose balance it is.
    ///   - network: The network that the balance belongs to.
    /// - Returns: The balance that every window showing the account on the network shares.
    private func shared(_ account: Account, on network: Network) -> WalletPrivateBalance {
        let key = Key(account, on: network)
        if let balance = balances[key] { return balance }
        let balance = WalletPrivateBalance(account: account, network: network, balances: privateBalances,
                                           transactions: transactions, pollInterval: pollInterval,
                                           followUpInterval: followUpInterval)
        balances[key] = balance
        return balance
    }

    /// Reads every observed balance again after each new provider connection.
    ///
    /// Reading the settings isn't a new connection, because nothing read through one yet, and neither is erasing
    /// them, as a reset does. The watch lasts as long as this store, and ends at the first change after it's gone.
    /// - Parameter providers: The provider settings that every window shares.
    private func watch(_ providers: ProviderStore) {
        let connections = Observations { providers.connection }
        Task { [weak self] in
            for await connection in connections {
                guard let self else { return }
                if ProviderClient.Endpoint.isNew(connection, after: self.connection) {
                    for balance in balances.values { balance.observeAgain() }
                }
                self.connection = connection
            }
        }
    }

    /// An account on a network, which identifies its shared balance.
    private struct Key: Hashable {
        let account: UUID
        let network: Network

        /// Identifies an account's balance on a network.
        /// - Parameters:
        ///   - account: The account whose balance it is.
        ///   - network: The network that the balance belongs to.
        init(_ account: Account, on network: Network) {
            self.account = account.id
            self.network = network
        }
    }
}
