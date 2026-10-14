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
    /// The window's portfolio, which follows the network that the window shows.
    let portfolio: WindowPortfolio
    /// The window's appearance editing.
    let settings: AppearanceSettingsModel
    /// The window's Security & Privacy navigation and steps.
    let security: SecurityCoordinator
    /// The window's RPC provider choices and key entry.
    let providers: ProvidersCoordinator

    /// Creates the window's workflows around the shared services.
    /// - Parameters:
    ///   - services: Shared services that retain no window-specific recovery draft.
    ///   - network: The network that the window shows first.
    init(services: AppServices, network: Network) {
        let router = services.makeWindowRouter(initialDestination: .restoringWallets)
        self.router = router
        onboarding = services.makeOnboardingCoordinator(router: router)
        startup = services.makeWindowStartup(router: router)
        portfolio = WindowPortfolio(network: network, makeCoordinator: services.makePortfolioCoordinator(for:))
        settings = services.makeAppearanceSettingsModel()
        security = services.makeSecurityCoordinator()
        providers = services.makeProvidersCoordinator()
    }
}
