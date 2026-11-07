import SwiftUI
@testable import widgets

struct TransactionResumptionRoot: View {
    let scene: ResumingScene
    let transactions: TransactionStore

    var body: some View {
        Color.clear
            .transactionResumption()
            .environment(transactions)
            .environment(scene.rpcStore)
            .task { await scene.rpcStore.load() }
            .environment(\.scenePhase, scene.phase)
    }
}
