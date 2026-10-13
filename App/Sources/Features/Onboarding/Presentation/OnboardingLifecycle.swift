import SwiftUI

extension OnboardingScene {
    /// Gives each coordinator its own onboarding navigation, draft presentation, and tasks, and runs the provider
    /// choice's reads, changes, and prompts while onboarding is on screen.
    /// - Returns: Onboarding whose presentation, including the provider choice's work, starts over when its coordinator
    ///   is replaced.
    func onboardingLifecycle() -> some View {
        modifier(ProvidersLifecycle(coordinator: providers))
            .id(ObjectIdentifier(coordinator))
    }
}
