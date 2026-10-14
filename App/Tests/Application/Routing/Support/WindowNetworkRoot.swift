import SwiftUI
@testable import widgets

/// Applies a window's network lifecycle and its portfolio observation, as a wallet window does.
struct WindowNetworkRoot: View {
    @Bindable var choice: NetworkChoice
    let portfolio: WindowPortfolio
    let account: Account
    let resetRevision: Revision
    let providerRevision: Revision

    var body: some View {
        Color.clear
            .windowNetwork($choice.network, portfolio: portfolio, resetRevision: resetRevision)
            .portfolioObservation(of: account, coordinator: portfolio.coordinator, providerRevision: providerRevision)
            // A hosted window isn't a SwiftUI scene, so the root reports the active scene that a shown window has.
            .environment(\.scenePhase, .active)
    }
}
