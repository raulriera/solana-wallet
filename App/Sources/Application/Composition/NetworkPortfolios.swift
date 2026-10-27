import Observation
import Portfolio
import RPC

/// Keeps one portfolio service for each network that a window shows, shared by every window on that network.
///
/// Windows on one network share its service's cache, subscriptions, and price pacing. Mainnet's service exists from
/// the start; another network's service is created when a window first shows that network, so a network that no
/// window shows has no service and does no work. After each change to the currency choice, from any window, every
/// service reads its prices again.
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
    ///   - currency: The currency choice that the prices convert with, whose changes have every service read its
    ///     prices again.
    ///   - make: Creates a network's service with its prices, or with none when the price provider quotes another
    ///     network.
    init(prices: any PriceProviding, currency: CurrencyStore,
         make: @escaping (Network, (any PriceProviding)?) -> Service) {
        self.prices = prices
        self.make = make
        _ = service(for: .mainnet)
        watch(currency)
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
                await self.pricesDidChange()
            }
        }
    }

    /// Has every created service read its prices again, each on its own.
    private func pricesDidChange() async {
        let created = created
        await withDiscardingTaskGroup { group in
            for service in created { group.addTask { await service.pricesDidChange() } }
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
