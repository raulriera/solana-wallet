import RPC
import SwiftUI
@testable import widgets

/// Reads a window's private balance on devnet in a given scene phase, as a wallet window does.
struct PrivateBalanceObservationRoot: View {
    let store: PrivateBalanceStore
    let account: widgets.Account
    let scenePhase: ScenePhase
    /// The shared provider settings, which a window's root supplies and reads.
    var providers = ProviderStore.inMemory()

    var body: some View {
        Color.clear
            .privateBalanceObservation(of: account, on: .devnet)
            .environment(store)
            .environment(providers)
            .task { await providers.load() }
            // A hosted window isn't a SwiftUI scene, so the root reports the phase that a shown window has.
            .environment(\.scenePhase, scenePhase)
    }
}
