import SwiftUI
@testable import widgets

struct TransactionResumptionRoot: View {
    let scene: ResumingScene
    let transactions: TransactionStore

    var body: some View {
        Color.clear
            .transactionResumption()
            .environment(transactions)
            .environment(scene.providers)
            .task { await scene.providers.load() }
            .environment(\.scenePhase, scene.phase)
    }
}
