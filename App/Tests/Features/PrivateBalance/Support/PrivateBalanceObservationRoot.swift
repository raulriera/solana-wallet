import RPC
import SwiftUI
@testable import widgets

struct PrivateBalanceObservationRoot: View {
    let store: PrivateBalanceStore
    let account: widgets.Account
    let scenePhase: ScenePhase
    var rpcStore = RPCStore.inMemory()

    var body: some View {
        Color.clear
            .observation(of: account, on: .devnet, in: PrivateBalanceStore.self)
            .environment(store)
            .environment(rpcStore)
            .task { await rpcStore.load() }
            .environment(\.scenePhase, scenePhase)
    }
}
