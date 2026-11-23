import Portfolio
import Privacy
import RPC
import SwiftUI
import Transactions

/// Presents an account's portfolio on a network in a split view: its tokens and their details, or why they can't load.
struct PortfolioSplitView: View {
    @Environment(\.palette) private var palette
    @Environment(\.cardStyle) private var cardStyle
    @Environment(PortfolioStore.self) private var portfolios
    @Environment(PrivateBalanceStore.self) private var privateBalances
    @State private var selection: Asset.ID?
    @State private var preferredColumn = NavigationSplitViewColumn.sidebar
    @State private var providerSetup: ProviderSetupModel<RPCConnectionError>?
    @State private var tokenAddition: TokenAdditionModel?
    @State private var isReceiving = false
    let account: Account
    let network: Network
    let connection: any ProviderConnecting<RPCConnectionError>
    let removal: TokenRemovalModel
    let privateBalance: PrivateBalanceModel

    var body: some View {
        let portfolio = portfolios.portfolio(for: account, on: network)
        let presentation = portfolio?.presentation ?? .blank
        let privateAssets = privateBalances.balance(for: account, on: network)?.privateAssets ?? []

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
                                           holdings: holdings, privateAssets: privateAssets)
                        case .rows:
                            TokenList(selection: $selection, holdings: holdings,
                                      privateAssets: privateAssets)
                        }
                    }
                    .animation(.default, value: portfolio?.snapshotRevision)
                    .refreshable { await refresh() }
                    .navigationTitle("Portfolio")
                    .navigationSubtitle(Text(portfolio?.error?.staleStatus ?? ""))
                    .sidebarColumn()
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Receive", systemImage: "qrcode", action: receive)
                                .tint(.primary)
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button("Add Token", systemImage: "plus", action: addToken)
                                .tint(.primary)
                        }
                    }
                } detail: {
                    if let holding = holdings.first(where: { $0.id == selection }) {
                        TokenDetailScreen(holding: holding, account: account, network: network,
                                          privateBalance: privateBalance)
                            .privateBalanceLifecycle()
                            .animation(.default, value: portfolio?.snapshotRevision)
                            .refreshable { await refreshDetail(of: holding) }
                    } else {
                        UnavailableScreen(title: "No Token Selected",
                                          message: "Select a token to see its balance and value.",
                                          systemImage: "wallet.bifold") {}
                            .toolbarTitleDisplayMode(.inline)
                    }
                }
                .navigationSplitViewStyle(.tabSection)
            }
        }
        .animation(.default, value: presentation)
        .environment(\.removeToken, TokenRemovalAction(removal: removal))
        .sheet(item: $providerSetup) { APIKeySheet(submission: $0) }
        .sheet(item: $tokenAddition) { TokenAdditionSheet(addition: $0, account: account, network: network) }
        .sheet(isPresented: $isReceiving) { ReceiveSheet(address: account.address, network: network) }
    }

    /// Opens the receive sheet.
    private func receive() {
        isReceiving = true
    }

    /// Opens the add-token sheet.
    private func addToken() {
        tokenAddition = TokenAdditionModel()
    }

    /// Opens provider setup.
    private func setUpProvider() {
        providerSetup = ProviderSetupModel(connection: connection)
    }

    /// Reads the wallet again.
    private func refresh() async {
        await portfolios.refresh(account, on: network)
    }

    /// Reads a token's details again, with the private balance for a token that private balances hold.
    ///
    /// - Parameter holding: The token whose details to read.
    private func refreshDetail(of holding: Holding) async {
        guard PrivateAsset(holding.id) != nil else { return await refresh() }
        async let privateRefresh: Void = privateBalances.refresh(account, on: network)
        await refresh()
        await privateRefresh
    }

    /// Loads the portfolio again.
    private func retry() {
        Task { await refresh() }
    }
}
