import Observation

/// Owns one window's navigation, which the window creates when it first appears; the services stay shared.
@MainActor
@Observable
final class WindowModel {
    /// The window's root navigation.
    let router: any WindowRouting
    /// The window's onboarding draft, which a reset replaces.
    var onboarding: any OnboardingCoordinating
    /// Restores the window's wallet when the window opens.
    let startup: any WindowStarting

    /// Creates the window's navigation around the shared services.
    /// - Parameter services: Shared services that retain no window-specific recovery draft.
    init(services: AppServices) {
        let router = services.makeWindowRouter()
        self.router = router
        onboarding = services.makeOnboardingCoordinator(router: router)
        startup = services.makeWindowStartup(router: router)
    }
}
