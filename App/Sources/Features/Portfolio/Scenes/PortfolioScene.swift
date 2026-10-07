import Portfolio
import SwiftUI

/// Presents the window's portfolio: its tokens and their details, or why they can't load.
///
/// The window observes the wallet; this section presents the coordinator's state and starts
/// explicit refreshes. A missing or rejected provider key replaces only this section.
struct PortfolioScene: View {
    @Environment(\.palette) private var palette
    @Environment(\.cardStyle) private var cardStyle
    @State private var selection: Holding.Identity?
    @State private var preferredColumn = NavigationSplitViewColumn.sidebar
    @State private var providerSetup: ProviderSubmission?
    let coordinator: any PortfolioCoordinating
    let connection: any ProviderConnecting
    let keyRevision: ProviderKeyRevision

    var body: some View {
        let presentation = PortfolioPresentation(coordinator.update)

        Group {
            switch presentation {
            case .blank:
                palette.background
                    .ignoresSafeArea()
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.background)
            case .unavailable(let failure):
                PortfolioUnavailableScreen(failure: failure,
                                           action: failure.requiresProviderSetup ? setUpProvider : retry)
            case .holdings:
                NavigationSplitView(preferredCompactColumn: $preferredColumn) {
                    Group {
                        switch cardStyle.layout {
                        case .cards:
                            TokenCardStack(selection: $selection, preferredColumn: $preferredColumn,
                                           holdings: coordinator.holdings)
                        case .rows:
                            TokenList(selection: $selection, holdings: coordinator.holdings)
                        }
                    }
                    // A new snapshot is the only change to the tokens, so its revision keys their motion.
                    .animation(.default, value: coordinator.update?.snapshotRevision)
                    .refreshable { await coordinator.refresh() }
                    .navigationTitle("Portfolio")
                    .navigationSubtitle(Text(coordinator.failure?.staleStatus ?? ""))
                    .sidebarColumnWidth()
                } detail: {
                    if let holding = coordinator.holdings.first(where: { $0.id == selection }),
                       let network = coordinator.update?.snapshot?.network {
                        TokenDetailScreen(holding: holding, network: network)
                    } else {
                        ContentUnavailableView("No Token Selected", systemImage: "wallet.bifold",
                                               description: Text("Select a token to see its balance and value."))
                            .foregroundStyle(palette.primaryText)
                            .background(palette.background)
                    }
                }
            }
        }
        .animation(.default, value: presentation)
        .sheet(item: $providerSetup) { ProviderSetupSheet(submission: $0) }
    }

    /// Opens provider setup; a saved key closes it, and every window observes again with that key.
    private func setUpProvider() {
        providerSetup = ProviderSubmission(connection: connection, revision: keyRevision) { providerSetup = nil }
    }

    /// Loads the portfolio again after a failed first load; the loading state shows until the result arrives.
    private func retry() {
        Task { await coordinator.refresh() }
    }
}
