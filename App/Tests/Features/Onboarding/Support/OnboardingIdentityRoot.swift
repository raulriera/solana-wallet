import SwiftUI
@testable import widgets

/// Hosts the production onboarding identity boundary and reports completed replacement updates.
struct OnboardingIdentityRoot: View {
    let scene: OnboardingScene
    let generation: Int
    let rendered: AsyncStream<Int>.Continuation

    var body: some View {
        scene
            .onboardingIdentity()
            .onChange(of: generation, initial: true) {
                rendered.yield(generation)
            }
    }
}
