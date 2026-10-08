import SwiftUI

/// Owns one window's feature state and applies its appearance lifecycle.
struct WindowRoot: View {
    @State private var router: any WindowRouting
    @State private var onboarding: any OnboardingCoordinating
    @State private var startup: any WindowStarting
    @State private var portfolio: any PortfolioCoordinating
    @State private var settings: AppearanceSettings
    @State private var security: SecurityFlow
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
        self.portfolio = services.makePortfolioCoordinator()
        self.settings = services.makeAppearanceSettings()
        self.security = services.makeSecurityFlow()
    }

    var body: some View {
        ZStack {
            switch router.destination {
            case .restoringWallets:
                Color.clear
            case .walletRestorationFailed:
                WalletUnavailableScreen(retry: { startupAttempt += 1 })
            case .onboarding:
                OnboardingScene(coordinator: onboarding, connection: services.providerConnection,
                                keyRevision: services.providerKeyRevision, pasteboard: services.recoveryPasteboard)
                    .onboardingIdentity()
            case .wallet(let account):
                WalletScene(account: account, portfolio: portfolio, settings: settings, connection: services.providerConnection,
                            keyRevision: services.providerKeyRevision, security: security, resetRevision: services.resetRevision)
            }
        }
        .animation(.default, value: router.destination)
        .windowRestoration(startup, router: router, attempt: startupAttempt)
        .windowReset(services, router: router, onboarding: $onboarding, security: security)
        .windowAppearance(services: services.appearance)
        .environment(\.artworkColors, services.artworkColors)
    }
}
