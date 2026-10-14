import Observation
import RPC

/// Owns one window's portfolio presentation and token removals for the network that the window shows.
///
/// Another network gets a new coordinator, so the previous network's observation and refreshes never reach it.
@MainActor
@Observable
final class WindowPortfolio {
    /// The portfolio presentation for the window's network.
    private(set) var coordinator: any PortfolioCoordinating
    /// The token removals that edit that portfolio's token lists.
    private(set) var tokenRemoval: TokenRemovalModel
    private let makeCoordinator: @MainActor (Network) -> any PortfolioCoordinating

    /// Creates the portfolio for the network that the window shows first.
    /// - Parameters:
    ///   - network: The window's network.
    ///   - makeCoordinator: Creates a window's presentation around a network's shared portfolio service.
    init(network: Network, makeCoordinator: @escaping @MainActor (Network) -> any PortfolioCoordinating) {
        let coordinator = makeCoordinator(network)
        self.coordinator = coordinator
        tokenRemoval = TokenRemovalModel(coordinator: coordinator)
        self.makeCoordinator = makeCoordinator
    }

    /// Replaces the portfolio and its token removals with ones for the window's new network.
    /// - Parameter network: The network that the window shows now.
    func show(_ network: Network) {
        let coordinator = makeCoordinator(network)
        self.coordinator = coordinator
        tokenRemoval = TokenRemovalModel(coordinator: coordinator)
    }
}
