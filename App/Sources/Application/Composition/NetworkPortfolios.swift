import Portfolio
import RPC

/// Keeps one portfolio service for each network that a window shows, shared by every window on that network.
///
/// Windows on one network share its service's cache, subscriptions, and price pacing. Mainnet's service exists from
/// the start; another network's service is created when a window first shows that network, so a network that no
/// window shows has no service and does no work.
@MainActor
final class NetworkPortfolios {
    /// A network's portfolio and token-list service.
    typealias Service = any PortfolioProviding & TokenListProviding

    private let prices: any PriceProviding
    private let make: (Network, (any PriceProviding)?) -> Service
    private var services: [Network: Service] = [:]

    /// Creates mainnet's service at once, and each other network's service when a window first shows it.
    /// - Parameters:
    ///   - prices: The price provider, which values holdings only on the network it quotes.
    ///   - make: Creates a network's service with its prices, or with none when the price provider quotes another
    ///     network.
    init(prices: any PriceProviding, make: @escaping (Network, (any PriceProviding)?) -> Service) {
        self.prices = prices
        self.make = make
        _ = service(for: .mainnet)
    }

    /// The services created so far: mainnet's, and each other network's once a window shows it.
    var created: [Service] { Array(services.values) }

    /// Creates one window's presentation around its network's shared service.
    /// - Parameter network: The network that the window shows.
    /// - Returns: A coordinator for that network, whose observation and refreshes belong to one window.
    func makeCoordinator(for network: Network) -> any PortfolioCoordinating {
        PortfolioCoordinator(service: service(for: network))
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
