import SwiftUI

/// Owns onboarding's navigation container within the window's appearance environment.
struct OnboardingScene: View {
    var body: some View {
        NavigationStack {
            // Destination screens are deferred until their individual UX review.
            WelcomeScreen(createWallet: {}, importWallet: {})
        }
    }
}
