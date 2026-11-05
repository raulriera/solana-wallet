import Observation
import Portfolio
import RPC
import Transactions

/// Keeps each wallet's portfolio on each network.
@MainActor
@Observable
final class PortfolioStore: Erasable {
    /// A network's portfolio and token-list service.
    typealias Service = any PortfolioProviding & TokenListProviding

    private var portfolios: [Key: WalletPortfolio] = [:]
    private let prices: any PriceProviding
    private let make: (Network, (any PriceProviding)?) -> Service
    @ObservationIgnored private var services: [Network: Service] = [:]

    /// Creates a store that keeps portfolios through each network's service.
    ///
    /// - Parameters:
    ///   - prices: The price provider.
    ///   - currency: The currency choice that prices convert to.
    ///   - providers: The provider settings that the services read through.
    ///   - priceChoice: The price provider choice that prices follow.
    ///   - make: A function that creates a network's service with its price provider, if any.
    init(prices: any PriceProviding, currency: CurrencyStore, providers: ProviderStore, priceChoice: PriceStore,
         make: @escaping (Network, (any PriceProviding)?) -> Service) {
        self.prices = prices
        self.make = make
        _ = service(for: .mainnet)
        Task { [weak self] in
            for await _ in Observations({ Pricing(currency: currency.settings,
                                                  provider: priceChoice.settings?.selection) }).changes() {
                guard let self else { return }
                await pricesDidChange()
            }
        }
        Task { [weak self] in
            for await _ in Observations({ providers.connection }).changes() {
                guard let self else { return }
                await providerDidChange()
            }
        }
    }

    /// Returns an account's portfolio on a network.
    ///
    /// - Parameters:
    ///   - account: The account whose wallet to read.
    ///   - network: The network whose portfolio to read.
    /// - Returns: The shared portfolio, or `nil` before anything observes it.
    func portfolio(for account: Account, on network: Network) -> WalletPortfolio? {
        portfolios[Key(account, on: network)]
    }

    /// Observes an account's wallet on a network for the lifetime of the calling task.
    ///
    /// - Parameters:
    ///   - account: The account whose wallet to observe.
    ///   - network: The network to observe the wallet on.
    func observe(_ account: Account, on network: Network) async {
        guard !Task.isCancelled else { return }
        await portfolio(for: Key(account, on: network)).observe()
    }

    /// Reads an observed account's wallet again.
    ///
    /// - Parameters:
    ///   - account: The account whose wallet to read.
    ///   - network: The network to read the wallet on.
    func refresh(_ account: Account, on network: Network) async {
        await portfolios[Key(account, on: network)]?.refresh()
    }

    /// Looks up the token at a mint address.
    ///
    /// - Parameters:
    ///   - mint: The mint address.
    ///   - network: The network to look the mint up on.
    /// - Returns: The token with its on-chain name and symbol, and its logo when the provider has one.
    /// - Throws: `TokenLookupError` when the address isn't a fungible token mint, or a request error.
    func token(at mint: Address, on network: Network) async throws -> TokenPreview {
        try await service(for: network).token(at: mint)
    }

    /// Adds a token to an account's list on a network.
    ///
    /// - Parameters:
    ///   - token: The token to add.
    ///   - account: The account whose list to change.
    ///   - network: The network whose list to change.
    /// - Throws: `TokenListError` for a full or unreadable list, or a file-system error if the list can't be saved.
    func add(_ token: ListedToken, for account: Account, on network: Network) async throws {
        try await service(for: network).addToken(token, for: account.address.value)
    }

    /// Removes a token from an account's list on a network.
    ///
    /// - Parameters:
    ///   - mint: The mint address of a listed token.
    ///   - account: The account whose list to change.
    ///   - network: The network whose list to change.
    /// - Throws: `TokenListError.unreadable` for an unreadable list, or a file-system error if the list can't be saved.
    func remove(_ mint: Address, for account: Account, on network: Network) async throws {
        try await service(for: network).removeToken(mint, for: account.address.value)
    }

    func erase() async throws {
        let keys = Array(portfolios.keys)
        let wallets = keys.map { (owner: $0.owner, service: service(for: $0.network)) }
        try await withThrowingDiscardingTaskGroup { group in
            for wallet in wallets { group.addTask { try await wallet.service.removeData(for: wallet.owner) } }
        }
        for key in keys { portfolios.removeValue(forKey: key)?.erase() }
    }

    /// Returns a wallet's portfolio on a network, creating it when needed.
    ///
    /// - Parameter key: The wallet and network.
    /// - Returns: The wallet's shared portfolio.
    private func portfolio(for key: Key) -> WalletPortfolio {
        if let portfolio = portfolios[key] { return portfolio }
        let portfolio = WalletPortfolio(owner: key.owner, service: service(for: key.network))
        portfolios[key] = portfolio
        return portfolio
    }

    /// Has every created service read its prices again after a change to the currency or the price provider.
    private func pricesDidChange() async {
        await forEachService { await $0.pricesDidChange() }
    }

    /// Restarts the services' work and the wallets' observations after a change to the provider connection.
    private func providerDidChange() async {
        await forEachService { try? await $0.providerDidChange() }
        for portfolio in portfolios.values { portfolio.observeAgain() }
    }

    /// Runs work on every created service concurrently.
    ///
    /// - Parameter work: The work for one service.
    private func forEachService(_ work: @escaping @Sendable (Service) async -> Void) async {
        let created = Array(services.values)
        await withDiscardingTaskGroup { group in
            for service in created { group.addTask { await work(service) } }
        }
    }

    /// Returns a network's service, creating it on the first request.
    ///
    /// - Parameter network: The network whose service to return.
    /// - Returns: The network's service.
    private func service(for network: Network) -> Service {
        if let service = services[network] { return service }
        let service = make(network, prices.network == network ? prices : nil)
        services[network] = service
        return service
    }

    /// The choices that portfolio prices depend on.
    nonisolated private struct Pricing: Equatable, Sendable {
        let currency: CurrencySettings
        let provider: PriceSettings.Provider

        /// Creates the choices that prices depend on, or `nil` until both are read.
        ///
        /// - Parameters:
        ///   - currency: The currency choice, or `nil` while it isn't read.
        ///   - provider: The price provider in use, or `nil` while it isn't read.
        init?(currency: CurrencySettings?, provider: PriceSettings.Provider?) {
            guard let currency, let provider else { return nil }
            self.currency = currency
            self.provider = provider
        }
    }

    /// A wallet's address and network, which identify its shared portfolio.
    private struct Key: Hashable {
        let owner: String
        let network: Network

        /// Creates the key for an account's wallet on a network.
        ///
        /// - Parameters:
        ///   - account: The account whose wallet it is.
        ///   - network: The network that the portfolio belongs to.
        init(_ account: Account, on network: Network) {
            owner = account.address.value
            self.network = network
        }
    }
}
