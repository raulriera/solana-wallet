import SwiftUI

/// Owns one window's feature state and applies its appearance lifecycle.
struct WindowRoot: View {
    @State private var router: any WindowRouting
    @State private var onboarding: any OnboardingCoordinating
    private let appearanceServices: AppearanceServices

    /// Seeds window-owned state from services that remain fixed for the window's lifetime.
    /// - Parameter services: Shared services that retain no window-specific recovery draft.
    init(services: AppServices) {
        appearanceServices = services.appearance
        let router = services.makeWindowRouter(initialDestination: .onboarding)
        self.router = router
        self.onboarding = services.makeOnboardingCoordinator(router: router)
    }

    var body: some View {
        ZStack {
            switch router.destination {
            case .onboarding:
                OnboardingScene(coordinator: onboarding)
            case .wallet:
                WalletReadyScreen()
            }
        }
        .animation(.default, value: router.destination)
        .windowAppearance(services: appearanceServices)
    }
}
