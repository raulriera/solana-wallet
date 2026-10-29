import SwiftUI
@testable import widgets

/// Hosts the production onboarding scene and reports completed updates.
struct OnboardingIdentityRoot: View {
    let scene: OnboardingScene
    let generation: Int
    let rendered: AsyncStream<Int>.Continuation
    /// The shared provider settings, which a window's root supplies.
    let providers: ProviderStore

    var body: some View {
        scene
            .environment(providers)
            .onChange(of: generation, initial: true) {
                rendered.yield(generation)
            }
    }
}
