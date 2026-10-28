import SwiftUI

extension OnboardingScene {
    /// Gives each coordinator its own onboarding navigation, draft presentation, provider choice, and tasks.
    /// - Returns: Onboarding whose presentation, including the provider choice's work, starts over when its coordinator
    ///   is replaced.
    func onboardingLifecycle() -> some View {
        id(ObjectIdentifier(coordinator))
    }
}
