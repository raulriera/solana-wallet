import SwiftUI

/// Owns one window's feature state and applies its appearance lifecycle.
struct WindowRoot: View {
    @State private var router: any WindowRouting
    @State private var onboarding: any OnboardingCoordinating
    @State private var startup: any WindowStarting
    @State private var portfolio: any PortfolioCoordinating
    @State private var tokenRemoval: TokenRemovalFlow
    @State private var settings: AppearanceSettings
    @State private var security: SecurityFlow
    @State private var providers: ProvidersFlow
    @State private var startupAttempt = 0
    private let services: AppServices

    /// Seeds window-owned state from services that remain fixed for the window's lifetime.
    /// - Parameter services: Shared services that retain no window-specific recovery draft.
    init(services: AppServices) {
        self.services = services
        let router = services.makeWindowRouter(initialDestination: .restoringWallets)
        self.router = router
        self.onboarding = services.makeOnboardingCoordinator(router: router)
        self.startup = services.makeWindowStartup(router: router)
        let portfolio = services.makePortfolioCoordinator()
        self.portfolio = portfolio
        self.tokenRemoval = TokenRemovalFlow(coordinator: portfolio)
        self.settings = services.makeAppearanceSettings()
        self.security = services.makeSecurityFlow()
        self.providers = services.makeProvidersFlow()
    }

    var body: some View {
        ZStack {
            switch router.destination {
            case .restoringWallets:
                Color.clear
            case .walletRestorationFailed:
                WalletUnavailableScreen(retry: { startupAttempt += 1 })
            case .onboarding:
                OnboardingScene(coordinator: onboarding, providers: providers, pasteboard: services.recoveryPasteboard)
                    .onboardingLifecycle()
            case .wallet(let account):
                WalletScene(account: account, portfolio: portfolio, tokenRemoval: tokenRemoval, settings: settings,
                            connection: services.providerConnection, providerRevision: services.providerRevision,
                            security: security, providers: providers, resetRevision: services.resetRevision)
            }
        }
        .animation(.default, value: router.destination)
        .windowRestoration(startup, router: router, attempt: startupAttempt)
        .windowReset(services, router: router, onboarding: $onboarding, security: security, providers: providers)
        .windowAppearance(services: services.appearance)
        .environment(\.artworkColors, services.artworkColors)
    }
}
