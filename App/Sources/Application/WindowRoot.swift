import SwiftUI

/// Owns one window's feature state and applies its appearance lifecycle.
struct WindowRoot: View {
    @State private var router: any WindowRouting
    @State private var onboarding: any OnboardingCoordinating
    @State private var startup: any WindowStarting
    @State private var startupAttempt = 0
    private let appearanceServices: AppearanceServices

    /// Seeds window-owned state from services that remain fixed for the window's lifetime.
    /// - Parameter services: Shared services that retain no window-specific recovery draft.
    init(services: AppServices) {
        appearanceServices = services.appearance
        let router = services.makeWindowRouter(initialDestination: .restoringWallets)
        self.router = router
        self.onboarding = services.makeOnboardingCoordinator(router: router)
        self.startup = services.makeWindowStartup(router: router)
    }

    var body: some View {
        ZStack {
            switch router.destination {
            case .restoringWallets:
                Color.clear
            case .walletRestorationFailed:
                WalletUnavailableScreen(retry: { startupAttempt += 1 })
            case .onboarding:
                OnboardingScene(coordinator: onboarding)
            case .wallet:
                WalletReadyScreen()
            }
        }
        .animation(.default, value: router.destination)
        .task(id: startupAttempt) { await startup.restore() }
        .windowAppearance(services: appearanceServices)
    }
}
