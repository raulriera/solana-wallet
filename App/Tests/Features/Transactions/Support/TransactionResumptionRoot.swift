import SwiftUI
@testable import widgets

/// Resumes the shared transactions' watches as a window's root does.
struct TransactionResumptionRoot: View {
    let scene: ResumingScene
    /// The shared transactions, which a window's root supplies.
    let transactions: TransactionStore

    var body: some View {
        Color.clear
            .transactionResumption(providerRevisions: scene.providerRevisions)
            .environment(transactions)
            // A hosted window isn't a SwiftUI scene, so the root reports the scene phase that the test sets.
            .environment(\.scenePhase, scene.phase)
    }
}
