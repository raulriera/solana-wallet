import SwiftUI
@testable import widgets

struct PortfolioObservationRoot: View {
    let portfolios: PortfolioStore
    let shown: ShownWallet
    var transactions = TransactionStore.unused
    var providers = ProviderStore.inMemory()

    var body: some View {
        Color.clear
            .portfolioObservation(of: shown.account, on: shown.network)
            .environment(portfolios)
            .environment(transactions)
            .environment(providers)
            .task { await providers.load() }
            .environment(\.scenePhase, shown.phase)
    }
}
