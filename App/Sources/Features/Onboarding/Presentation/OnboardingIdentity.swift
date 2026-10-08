import SwiftUI

extension OnboardingScene {
    /// Gives each coordinator its own onboarding navigation, draft presentation, and tasks.
    /// - Returns: Onboarding whose presentation starts over when its coordinator is replaced.
    func onboardingIdentity() -> some View {
        id(ObjectIdentifier(coordinator))
    }
}
