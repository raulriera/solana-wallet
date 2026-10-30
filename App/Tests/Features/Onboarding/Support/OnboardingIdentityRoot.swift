import SwiftUI
@testable import widgets

struct OnboardingIdentityRoot: View {
    let scene: OnboardingScene
    let generation: Int
    let rendered: AsyncStream<Int>.Continuation
    let providers: ProviderStore

    var body: some View {
        scene
            .environment(providers)
            .onChange(of: generation, initial: true) {
                rendered.yield(generation)
            }
    }
}
