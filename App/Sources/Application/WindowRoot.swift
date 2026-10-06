import SwiftUI

/// Owns one window's feature state and applies its appearance lifecycle.
struct WindowRoot: View {
    @State private var router: any WindowRouting
    @State private var onboarding: any OnboardingCoordinating
    @State private var startup: any WindowStarting
    @State private var portfolio: any PortfolioCoordinating
    @State private var settings: AppearanceSettings
    @State private var startupAttempt = 0
    private let appearanceServices: AppearanceServices
    private let providerConnection: any ProviderConnecting
    private let providerKeyRevision: ProviderKeyRevision
    private let recoveryPasteboard: any RecoveryCopying

    /// Seeds window-owned state from services that remain fixed for the window's lifetime.
    /// - Parameter services: Shared services that retain no window-specific recovery draft.
    init(services: AppServices) {
        appearanceServices = services.appearance
        providerConnection = services.providerConnection
        providerKeyRevision = services.providerKeyRevision
        recoveryPasteboard = services.recoveryPasteboard
        let router = services.makeWindowRouter(initialDestination: .restoringWallets)
        self.router = router
        self.onboarding = services.makeOnboardingCoordinator(router: router)
        self.startup = services.makeWindowStartup(router: router)
        self.portfolio = services.makePortfolioCoordinator()
        self.settings = services.makeAppearanceSettings()
    }

    var body: some View {
        ZStack {
            switch router.destination {
            case .restoringWallets:
                Color.clear
            case .walletRestorationFailed:
                WalletUnavailableScreen(retry: { startupAttempt += 1 })
            case .onboarding:
                OnboardingScene(coordinator: onboarding, connection: providerConnection, keyRevision: providerKeyRevision,
                                pasteboard: recoveryPasteboard)
            case .wallet(let account):
                WalletScene(account: account, portfolio: portfolio, settings: settings, connection: providerConnection,
                            keyRevision: providerKeyRevision)
            }
        }
        .animation(.default, value: router.destination)
        .windowRestoration(startup, router: router, attempt: startupAttempt)
        .windowAppearance(services: appearanceServices)
    }
}
