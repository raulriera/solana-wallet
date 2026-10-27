import Observation
import Portfolio
import RPC

/// Keeps one portfolio service for each network that a window shows, shared by every window on that network.
///
/// Windows on one network share its service's cache, subscriptions, and price pacing. Mainnet's service exists from
/// the start; another network's service is created when a window first shows that network, so a network that no
/// window shows has no service and does no work. After each change to the currency choice, from any window, every
/// service reads its prices again. After each new provider connection, every service ends the previous provider's
/// work before ``connection`` follows, so windows observe again only once that work has ended.
@MainActor
@Observable
final class NetworkPortfolios {
    /// A network's portfolio and token-list service.
    typealias Service = any PortfolioProviding & TokenListProviding

    /// The provider connection that the services read through, or `nil` until the provider settings are read and
    /// after they're erased.
    ///
    /// It follows the shared settings' connection once every service has ended the previous provider's work, so an
    /// observation that starts when it changes never meets that work's end.
    private(set) var connection: ProviderClient.Endpoint?
    private let prices: any PriceProviding
    private let make: (Network, (any PriceProviding)?) -> Service
    @ObservationIgnored private var services: [Network: Service] = [:]

    /// Creates mainnet's service at once, and each other network's service when a window first shows it.
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

    /// The services created so far: mainnet's, and each other network's once a window shows it.
    var created: [Service] { Array(services.values) }

    /// Creates one window's presentation around its network's shared service.
    /// - Parameter network: The network that the window shows.
    /// - Returns: A coordinator for that network, whose observation and refreshes belong to one window.
    func makeCoordinator(for network: Network) -> any PortfolioCoordinating {
        PortfolioCoordinator(service: service(for: network))
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
                await self.forEachService { await $0.pricesDidChange() }
            }
        }
    }

    /// Follows each new provider connection once every created service has ended the previous provider's work.
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
                    await self.forEachService { try? await $0.providerDidChange() }
                }
                self.connection = connection
            }
        }
    }

    /// Runs work on every created service, each on its own.
    /// - Parameter work: The work for one service, such as reading its prices again.
    private func forEachService(_ work: @escaping @Sendable (Service) async -> Void) async {
        let created = created
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
}
