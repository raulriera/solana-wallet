import Observation
import Portfolio
import RPC
import Transactions

/// Keeps each wallet's portfolio on each network, shared by every window that shows it, over one portfolio service for
/// each network.
///
/// Windows on one network share its service's cache, subscriptions, and price pacing, and windows that show the same
/// wallet on the same network share its ``WalletPortfolio``. Mainnet's service exists from the start; another network's
/// service is created when a window first observes a wallet there, so a network that no window shows does no work.
/// After each change to the currency choice, from any window, every service reads its prices again. After each new
/// provider connection, every service ends the previous provider's work, the observed wallets observe again, and only
/// then does ``connection`` follow.
@MainActor
@Observable
final class PortfolioStore: Erasable {
    /// A network's portfolio and token-list service.
    typealias Service = any PortfolioProviding & TokenListProviding

    /// The provider connection that the services read through, or `nil` until the provider settings are read and
    /// after they're erased.
    private(set) var connection: ProviderClient.Endpoint?
    /// Each wallet's portfolio on each network that a window observed, kept for the next window that shows it.
    private var portfolios: [Key: WalletPortfolio] = [:]
    private let prices: any PriceProviding
    private let make: (Network, (any PriceProviding)?) -> Service
    @ObservationIgnored private var services: [Network: Service] = [:]

    /// Creates mainnet's service at once, and each other network's service when a window first observes a wallet there.
    /// - Parameters:
    ///   - prices: The price provider, which values holdings only on the network it quotes.
    ///   - currency: The currency choice that the prices convert with, whose changes have every service read its
    ///     prices again.
    ///   - providers: The provider settings that the services read through, whose new connections end every
    ///     service's work with the previous provider.
    ///   - make: Creates a network's service with its prices, or with none when the price provider quotes another
    ///     network.
    init(prices: any PriceProviding, currency: CurrencyStore, providers: ProviderStore,
         make: @escaping (Network, (any PriceProviding)?) -> Service) {
        self.prices = prices
        self.make = make
        _ = service(for: .mainnet)
        watch(currency)
        watch(providers)
    }

    /// An account's portfolio on a network.
    /// - Parameters:
    ///   - account: The account whose wallet to read.
    ///   - network: The network whose portfolio to read.
    /// - Returns: The portfolio that every window showing the account on the network shares, or `nil` before any
    ///   window observes it.
    func portfolio(for account: Account, on network: Network) -> WalletPortfolio? {
        portfolios[Key(account, on: network)]
    }

    /// Observes an account's wallet on a network for the lifetime of the calling task.
    ///
    /// Callers that observe the same wallet on the same network, such as two windows, share one observation; when the
    /// last of them ends, its progress settles while its holdings stay.
    /// - Parameters:
    ///   - account: The account whose wallet to observe.
    ///   - network: The network to observe the wallet on.
    func observe(_ account: Account, on network: Network) async {
        guard !Task.isCancelled else { return }
        await portfolio(for: Key(account, on: network)).observe()
    }

    /// Reads an observed account's wallet again, awaiting the read for pull-to-refresh.
    ///
    /// Every window that observes the wallet receives the results. Cancelling the caller stops its wait, not the read.
    /// A wallet that nothing observes isn't read.
    /// - Parameters:
    ///   - account: The account whose wallet to read.
    ///   - network: The network to read the wallet on.
    func refresh(_ account: Account, on network: Network) async {
        await portfolios[Key(account, on: network)]?.refresh()
    }

    /// Looks up a pasted mint address, so the person can check the token before adding it.
    /// - Parameters:
    ///   - mint: The pasted mint address.
    ///   - network: The network to look the mint up on.
    /// - Returns: The token with its on-chain name and symbol, and its logo when the provider has one.
    /// - Throws: `TokenLookupError` when the address isn't a fungible token mint, or a request error.
    func token(at mint: Address, on network: Network) async throws -> TokenPreview {
        try await service(for: network).token(at: mint)
    }

    /// Adds a token to an account's list on a network; an observed wallet then reads its balances again.
    /// - Parameters:
    ///   - token: A token that ``token(at:on:)`` found.
    ///   - account: The account whose list to change.
    ///   - network: The network whose list to change.
    /// - Throws: `TokenListError` for a full or unreadable list, or a file-system error if the list can't be saved.
    func add(_ token: ListedToken, for account: Account, on network: Network) async throws {
        try await service(for: network).addToken(token, for: account.address.value)
    }

    /// Removes a token from an account's list on a network; the service sends the next snapshot without it.
    /// - Parameters:
    ///   - mint: The mint address of a listed token.
    ///   - account: The account whose list to change.
    ///   - network: The network whose list to change.
    /// - Throws: `TokenListError.unreadable` for an unreadable list, or a file-system error if the list can't be saved.
    func remove(_ mint: Address, for account: Account, on network: Network) async throws {
        try await service(for: network).removeToken(mint, for: account.address.value)
    }

    /// Ends every wallet's work, removes its saved holdings and token list, and forgets its portfolio, as Reset App
    /// does, so no read that's running saves a deleted wallet's holdings again and no window shows them.
    /// - Throws: A file-system error if a wallet's saved holdings or token list can't be removed, which keeps every
    ///   portfolio.
    func erase() async throws {
        let keys = Array(portfolios.keys)
        let wallets = keys.map { (owner: $0.owner, service: service(for: $0.network)) }
        try await withThrowingDiscardingTaskGroup { group in
            for wallet in wallets { group.addTask { try await wallet.service.removeData(for: wallet.owner) } }
        }
        // A wallet that a window starts to observe meanwhile keeps its portfolio, whose work didn't end.
        for key in keys { portfolios.removeValue(forKey: key)?.erase() }
    }

    /// Returns a wallet's portfolio on a network, creating it, and the network's service, on the first observation.
    /// - Parameter key: The wallet and network.
    /// - Returns: The portfolio that every observer of the wallet on the network shares.
    private func portfolio(for key: Key) -> WalletPortfolio {
        if let portfolio = portfolios[key] { return portfolio }
        let portfolio = WalletPortfolio(owner: key.owner, service: service(for: key.network))
        portfolios[key] = portfolio
        return portfolio
    }

    /// Has every created service read its prices again after each change to the currency choice.
    ///
    /// Reading the choice isn't a change, because prices read the choice themselves, and neither is erasing it, which
    /// leaves it unread until the next read, as a reset does. The watch lasts as long as these services, and ends at the
    /// first change after they're gone.
    /// - Parameter currency: The currency choice that every window shares.
    private func watch(_ currency: CurrencyStore) {
        let choices = Observations { currency.settings }
        Task { [weak self] in
            var isRead = false
            // The store tells observers only of a different choice, which is `nil` while it isn't read.
            for await choice in choices {
                let wasRead = isRead
                isRead = choice != nil
                guard wasRead, isRead else { continue }
                guard let self else { return }
                await forEachService { await $0.pricesDidChange() }
            }
        }
    }

    /// Follows each new provider connection once every created service has ended the previous provider's work and the
    /// observed wallets observe again.
    ///
    /// Reading the settings isn't a new connection, because nothing read through one yet, and neither is erasing
    /// them, as a reset does; both apply at once. The store also tells of equal connections, such as after a new key
    /// while another provider is in use, which change nothing. The watch lasts as long as these services, and ends at
    /// the first change after they're gone.
    /// - Parameter providers: The provider settings that every window shares.
    private func watch(_ providers: ProviderStore) {
        let connections = Observations { providers.connection }
        Task { [weak self] in
            for await connection in connections {
                guard let self else { return }
                guard connection != self.connection else { continue }
                if ProviderClient.Endpoint.isNew(connection, after: self.connection) {
                    // Logos that one service can't remove, as on a full disk, don't keep another from ending its
                    // work; they stay until a later change.
                    await forEachService { try? await $0.providerDidChange() }
                    // Ending the work ended the observations, which every window shares.
                    for portfolio in portfolios.values { portfolio.observeAgain() }
                }
                self.connection = connection
            }
        }
    }

    /// Runs work on every created service, each on its own.
    /// - Parameter work: The work for one service, such as reading its prices again.
    private func forEachService(_ work: @escaping @Sendable (Service) async -> Void) async {
        let created = Array(services.values)
        await withDiscardingTaskGroup { group in
            for service in created { group.addTask { await work(service) } }
        }
    }

    /// Returns a network's service, creating it on the first request.
    /// - Parameter network: The network whose service to return.
    /// - Returns: The service that every window on the network shares.
    private func service(for network: Network) -> Service {
        if let service = services[network] { return service }
        // Quotes identify one network's mints, so other networks show amounts without value.
        let service = make(network, prices.network == network ? prices : nil)
        services[network] = service
        return service
    }

    /// A wallet on a network, which identifies its shared portfolio; accounts with the same address share it.
    private struct Key: Hashable {
        let owner: String
        let network: Network

        /// Identifies an account's wallet on a network.
        /// - Parameters:
        ///   - account: The account whose wallet it is.
        ///   - network: The network that the portfolio belongs to.
        init(_ account: Account, on network: Network) {
            owner = account.address.value
            self.network = network
        }
    }
}
