import Portfolio
import SwiftUI

/// Presents the window's portfolio: its tokens and their details, or why they can't load.
///
/// The window observes the wallet; this section presents the coordinator's state and starts
/// explicit refreshes. A failure that only provider setup fixes replaces only this section.
struct PortfolioScene: View {
    @Environment(\.palette) private var palette
    @Environment(\.cardStyle) private var cardStyle
    @State private var selection: Holding.Identity?
    @State private var preferredColumn = NavigationSplitViewColumn.sidebar
    @State private var providerSetup: ProviderSetupModel<ProviderConnectionError>?
    @State private var tokenAddition: TokenAdditionModel?
    let coordinator: any PortfolioCoordinating
    let connection: any ProviderConnecting<ProviderConnectionError>
    /// The window's token removals, which the parent runs with ``tokenRemovalLifecycle()``.
    let removal: TokenRemovalModel
    /// The window's private balance, which the parent reads with ``privateBalanceObservation(of:model:providerRevisions:)``
    /// and SOL's details turn on.
    let privateBalance: PrivateBalanceModel

    var body: some View {
        let presentation = PortfolioPresentation(coordinator.update)

        // One container, so the lifecycle modifiers below run once instead of once for each presentation.
        ZStack {
            switch presentation {
            case .blank:
                palette.background
                    .ignoresSafeArea()
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.background)
            case .unavailable(let error):
                PortfolioUnavailableScreen(error: error,
                                           action: error.requiresProviderSetup ? setUpProvider : retry)
            case .holdings:
                NavigationSplitView(preferredCompactColumn: $preferredColumn) {
                    Group {
                        switch cardStyle.layout {
                        case .cards:
                            TokenCardStack(selection: $selection, preferredColumn: $preferredColumn,
                                           holdings: coordinator.holdings,
                                           hasPrivateBalance: privateBalance.hasBalance)
                        case .rows:
                            TokenList(selection: $selection, holdings: coordinator.holdings,
                                      hasPrivateBalance: privateBalance.hasBalance)
                        }
                    }
                    // A new snapshot is the only change to the tokens, so its revision keys their motion.
                    .animation(.default, value: coordinator.update?.snapshotRevision)
                    .refreshable { await coordinator.refresh() }
                    .navigationTitle("Portfolio")
                    .navigationSubtitle(Text(coordinator.error?.staleStatus ?? ""))
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            // Toolbar buttons keep the system's monochrome look; the theme's tint is for content.
                            Button("Add Token", systemImage: "plus", action: addToken)
                                .tint(.primary)
                        }
                    }
                    .sidebarColumnWidth()
                } detail: {
                    if let holding = coordinator.holdings.first(where: { $0.id == selection }) {
                        TokenDetailScreen(holding: holding, removal: removal, privateBalance: privateBalance)
                            .privateBalanceLifecycle()
                            // New prices roll into place, as they do in the token list.
                            .animation(.default, value: coordinator.update?.snapshotRevision)
                            .refreshable { await refreshDetail(of: holding) }
                    } else {
                        ContentUnavailableView("No Token Selected", systemImage: "wallet.bifold",
                                               description: Text("Select a token to see its balance and value.")
                                                .foregroundStyle(palette.secondaryText))
                            .drawOnAppear()
                            .foregroundStyle(palette.primaryText, palette.secondaryText)
                            .background(palette.background)
                            // Inline like a token's details, so a cleared selection leaves no empty large title.
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
                .navigationSplitViewStyle(.tabSection)
            }
        }
        .animation(.default, value: presentation)
        .sheet(item: $providerSetup) { ProviderSetupSheet(submission: $0) }
        .sheet(item: $tokenAddition) { TokenAdditionSheet(addition: $0) }
        // Another network's portfolio has its own tokens, so the window starts again on the token list.
        .onChange(of: ObjectIdentifier(coordinator)) {
            selection = nil
            preferredColumn = .sidebar
        }
    }

    /// Opens the add-token sheet; an added token closes it and appears with the next balances.
    private func addToken() {
        tokenAddition = TokenAdditionModel(coordinator: coordinator)
    }

    /// Opens provider setup; a saved key closes it, and every window observes again with that key.
    private func setUpProvider() {
        providerSetup = ProviderSetupModel(connection: connection)
    }

    /// Reads a token's details again: the portfolio, and for SOL its private balance too.
    /// - Parameter holding: The token whose details show.
    private func refreshDetail(of holding: Holding) async {
        guard holding.id == .nativeSOL else { return await coordinator.refresh() }
        async let privateRefresh: Void = privateBalance.refresh()
        await coordinator.refresh()
        await privateRefresh
    }

    /// Loads the portfolio again after a failed first load; the loading state shows until the result arrives.
    private func retry() {
        Task { await coordinator.refresh() }
    }
}
