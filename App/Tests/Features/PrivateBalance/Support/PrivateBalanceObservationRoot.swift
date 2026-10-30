import RPC
import SwiftUI
@testable import widgets

struct PrivateBalanceObservationRoot: View {
    let store: PrivateBalanceStore
    let account: widgets.Account
    let scenePhase: ScenePhase
    var providers = ProviderStore.inMemory()

    var body: some View {
        Color.clear
            .privateBalanceObservation(of: account, on: .devnet)
            .environment(store)
            .environment(providers)
            .task { await providers.load() }
            .environment(\.scenePhase, scenePhase)
    }
}
