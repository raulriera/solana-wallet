import SwiftUI
@testable import widgets

/// Observes the shown wallet in the shared portfolios, as a wallet window does.
struct PortfolioObservationRoot: View {
    /// The shared portfolios, which a window's root supplies.
    let portfolios: PortfolioStore
    let shown: ShownWallet
    /// The shared transactions, which a window's root supplies.
    var transactions = TransactionStore.unused
    /// The shared provider settings, which a window's root supplies and reads.
    var providers = ProviderStore.inMemory()

    var body: some View {
        Color.clear
            .portfolioObservation(of: shown.account, on: shown.network)
            .environment(portfolios)
            .environment(transactions)
            .environment(providers)
            .task { await providers.load() }
            // A hosted window isn't a SwiftUI scene, so the root reports the scene phase that a shown window has.
            .environment(\.scenePhase, shown.phase)
    }
}
