import RPC
import SwiftUI
@testable import widgets

/// Observes a wallet on the shown portfolio on devnet, as a wallet window does.
struct PortfolioObservationRoot: View {
    let shown: ShownPortfolio
    let account: widgets.Account
    /// The shared transactions, which a window's root supplies.
    var transactions = TransactionStore.unused

    var body: some View {
        Color.clear
            .portfolioObservation(of: account, on: .devnet, coordinator: shown.coordinator,
                                  providerRevisions: ProviderRevisions())
            .environment(transactions)
            // A hosted window isn't a SwiftUI scene, so the root reports the active scene that a shown window has.
            .environment(\.scenePhase, .active)
    }
}
