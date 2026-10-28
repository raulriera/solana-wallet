import Portfolio
import RPC
import SwiftUI

/// Presents an account's portfolio on a network in a split view: its tokens and their details, or why they can't load.
///
/// The window observes the wallet; this view reads its state from the shared portfolios and starts explicit
/// refreshes. A failure that only provider setup fixes replaces only the Portfolio tab.
struct PortfolioSplitView: View {
    @Environment(\.palette) private var palette
    @Environment(\.cardStyle) private var cardStyle
    @Environment(PortfolioStore.self) private var portfolios
    @Environment(PrivateBalanceStore.self) private var privateBalances
    @State private var selection: Holding.Identity?
    @State private var preferredColumn = NavigationSplitViewColumn.sidebar
    @State private var providerSetup: ProviderSetupModel<ProviderConnectionError>?
    @State private var tokenAddition: TokenAdditionModel?
    /// The account whose portfolio shows.
    let account: Account
    /// The network whose portfolio shows.
    let network: Network
    let connection: any ProviderConnecting<ProviderConnectionError>
    /// The portfolio's token removals, which run with ``tokenRemovalLifecycle()`` and token details start with
    /// ``TokenRemovalAction``.
    let removal: TokenRemovalModel
    /// The portfolio's private-balance workflows, which SOL's details run; the window reads the balance itself with
    /// ``privateBalanceObservation(of:on:)``.
    let privateBalance: PrivateBalanceModel

    var body: some View {
        let portfolio = portfolios.portfolio(for: account, on: network)
        let presentation = portfolio?.presentation ?? .blank
        let hasPrivateBalance = privateBalances.balance(for: account, on: network)?.hasBalance ?? false

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
                let holdings = portfolio?.holdings ?? []
                NavigationSplitView(preferredCompactColumn: $preferredColumn) {
                    Group {
                        switch cardStyle.layout {
                        case .cards:
                            TokenCardStack(selection: $selection, preferredColumn: $preferredColumn,
                                           holdings: holdings, hasPrivateBalance: hasPrivateBalance)
                        case .rows:
                            TokenList(selection: $selection, holdings: holdings,
                                      hasPrivateBalance: hasPrivateBalance)
                        }
                    }
                    // A new snapshot is the only change to the tokens, so its revision keys their motion.
                    .animation(.default, value: portfolio?.snapshotRevision)
                    .refreshable { await refresh() }
                    .navigationTitle("Portfolio")
                    .navigationSubtitle(Text(portfolio?.error?.staleStatus ?? ""))
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            // Toolbar buttons keep the system's monochrome look; the theme's tint is for content.
                            Button("Add Token", systemImage: "plus", action: addToken)
                                .tint(.primary)
                        }
                    }
                    .sidebarColumnWidth()
                } detail: {
                    if let holding = holdings.first(where: { $0.id == selection }) {
                        TokenDetailScreen(holding: holding, account: account, network: network,
                                          privateBalance: privateBalance)
                            .privateBalanceLifecycle()
                            // New prices roll into place, as they do in the token list.
                            .animation(.default, value: portfolio?.snapshotRevision)
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
        // The token's details remove it without holding the portfolio's removals.
        .environment(\.removeToken, TokenRemovalAction(removal: removal))
        .sheet(item: $providerSetup) { ProviderSetupSheet(submission: $0) }
        .sheet(item: $tokenAddition) { TokenAdditionSheet(addition: $0, account: account, network: network) }
    }

    /// Opens the add-token sheet; an added token closes it and appears with the next balances.
    private func addToken() {
        tokenAddition = TokenAdditionModel()
    }

    /// Opens provider setup; a saved key closes it, and every window observes again with that key.
    private func setUpProvider() {
        providerSetup = ProviderSetupModel(connection: connection)
    }

    /// Reads the wallet again, awaiting the read for pull-to-refresh.
    private func refresh() async {
        await portfolios.refresh(account, on: network)
    }

    /// Reads a token's details again: the portfolio, and for SOL its private balance too.
    /// - Parameter holding: The token whose details show.
    private func refreshDetail(of holding: Holding) async {
        guard holding.id == .nativeSOL else { return await refresh() }
        async let privateRefresh: Void = privateBalances.refresh(account, on: network)
        await refresh()
        await privateRefresh
    }

    /// Loads the portfolio again after a failed first load; the loading state shows until the result arrives.
    private func retry() {
        Task { await refresh() }
    }
}
