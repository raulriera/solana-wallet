import SwiftUI

/// Returns a window to onboarding with a fresh draft after the app resets.
///
/// Leaving the wallet ends its tabs' workflows, and the fresh draft starts onboarding's own, so none is left open.
private struct WindowReset: ViewModifier {
    @Binding var onboarding: any OnboardingCoordinating
    let services: AppServices
    let router: any WindowRouting

    /// Starts onboarding over each time any window resets the app.
    /// - Parameter content: The window's root destinations.
    /// - Returns: Content that leaves deleted wallets after a reset.
    func body(content: Content) -> some View {
        content
            .onChange(of: services.resetRevision.value) {
                // The finished draft still refers to a deleted wallet, so onboarding starts with a new one.
                onboarding = services.makeOnboardingCoordinator(router: router)
                router.route(to: .onboarding)
            }
    }
}

extension View {
    /// Returns this window to onboarding after any window resets the app.
    /// - Parameters:
    ///   - services: The shared services that count resets and create onboarding drafts.
    ///   - router: The window's navigation.
    ///   - onboarding: The window's onboarding draft, replaced after a reset.
    /// - Returns: A view whose window starts over after a reset.
    func windowReset(_ services: AppServices, router: any WindowRouting,
                     onboarding: Binding<any OnboardingCoordinating>) -> some View {
        modifier(WindowReset(onboarding: onboarding, services: services, router: router))
    }
}
