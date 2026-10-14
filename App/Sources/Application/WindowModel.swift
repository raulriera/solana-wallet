import Observation
import RPC

/// Owns one window's workflows, which the window creates when it first appears; the services stay shared.
@MainActor
@Observable
final class WindowModel {
    /// The window's root navigation.
    let router: any WindowRouting
    /// The window's onboarding draft, which a reset replaces.
    var onboarding: any OnboardingCoordinating
    /// Restores the window's wallet when the window opens.
    let startup: any WindowStarting
    /// The portfolio presentation for the network that the window shows.
    private(set) var portfolio: any PortfolioCoordinating
    /// The token removals that edit that portfolio's token lists.
    private(set) var tokenRemoval: TokenRemovalModel
    /// The window's appearance editing.
    let settings: AppearanceSettingsModel
    /// The window's Security & Privacy navigation and steps.
    let security: SecurityCoordinator
    /// The window's RPC provider choices and key entry.
    let providers: ProvidersCoordinator
    private let services: AppServices

    /// Creates the window's workflows around the shared services.
    /// - Parameters:
    ///   - services: Shared services that retain no window-specific recovery draft.
    ///   - network: The network that the window shows first.
    init(services: AppServices, network: Network) {
        let router = services.makeWindowRouter(initialDestination: .restoringWallets)
        self.router = router
        onboarding = services.makeOnboardingCoordinator(router: router)
        startup = services.makeWindowStartup(router: router)
        let portfolio = services.makePortfolioCoordinator(for: network)
        self.portfolio = portfolio
        tokenRemoval = TokenRemovalModel(coordinator: portfolio)
        settings = services.makeAppearanceSettingsModel()
        security = services.makeSecurityCoordinator()
        providers = services.makeProvidersCoordinator()
        self.services = services
    }

    /// Replaces the portfolio and its token removals with ones for the window's new network, so the previous
    /// network's observation and refreshes never reach them.
    /// - Parameter network: The network that the window shows now.
    func show(_ network: Network) {
        portfolio = services.makePortfolioCoordinator(for: network)
        tokenRemoval = TokenRemovalModel(coordinator: portfolio)
    }
}
