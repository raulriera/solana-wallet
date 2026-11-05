import SwiftUI
@testable import widgets

struct OnboardingIdentityRoot: View {
    let scene: OnboardingScene
    let generation: Int
    let rendered: AsyncStream<Int>.Continuation
    let rpcStore: RPCStore

    var body: some View {
        scene
            .environment(rpcStore)
            .onChange(of: generation, initial: true) {
                rendered.yield(generation)
            }
    }
}
