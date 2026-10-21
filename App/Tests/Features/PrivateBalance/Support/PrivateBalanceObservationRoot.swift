import SwiftUI
@testable import widgets

/// Reads a window's private balance in a given scene phase, as a wallet window does.
struct PrivateBalanceObservationRoot: View {
    let model: PrivateBalanceModel
    let account: Account
    let scenePhase: ScenePhase

    var body: some View {
        Color.clear
            .privateBalanceObservation(of: account, model: model, providerRevisions: ProviderRevisions())
            // A hosted window isn't a SwiftUI scene, so the root reports the phase that a shown window has.
            .environment(\.scenePhase, scenePhase)
    }
}
