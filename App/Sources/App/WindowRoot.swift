import SwiftUI

/// Owns one window's feature state and applies its appearance lifecycle.
struct WindowRoot: View {
    @State private var onboarding: any OnboardingCoordinating
    private let appearanceServices: AppearanceServices

    /// Seeds independent onboarding state once for this window's lifetime.
    /// - Parameter services: Shared services that retain no window-specific recovery draft.
    init(services: AppServices) {
        appearanceServices = services.appearance
        self.onboarding = services.makeOnboardingCoordinator()
    }

    var body: some View {
        OnboardingScene(coordinator: onboarding)
            .windowAppearance(services: appearanceServices)
    }
}
