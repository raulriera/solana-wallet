import SwiftUI
@testable import widgets

/// Observes a wallet on the shown portfolio, as a wallet window does.
struct PortfolioObservationRoot: View {
    let shown: ShownPortfolio
    let account: Account

    var body: some View {
        Color.clear
            .portfolioObservation(of: account, coordinator: shown.coordinator, providerRevision: Revision())
            // A hosted window isn't a SwiftUI scene, so the root reports the active scene that a shown window has.
            .environment(\.scenePhase, .active)
    }
}
