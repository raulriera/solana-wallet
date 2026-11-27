import RPC
import SwiftUI

/// Shows the Settings destinations in a sidebar and the selected one's screens.
struct SettingsSplitView: View {
    @State private var selection: SettingsDestination?
    @Binding var network: Network
    let settings: AppearanceSettingsModel
    @Binding var account: Account
    let security: SecurityCoordinator
    let rpcCoordinator: RPCCoordinator
    let pricesCoordinator: PricesCoordinator

    /// Creates the Settings split view.
    ///
    /// - Parameters:
    ///   - settings: The window's appearance settings workflow.
    ///   - account: The window's account.
    ///   - network: The window's network.
    ///   - security: The Security & Privacy workflow.
    ///   - rpcCoordinator: The RPC provider workflow.
    ///   - pricesCoordinator: The price provider workflow.
    init(settings: AppearanceSettingsModel, account: Binding<Account>,
         network: Binding<Network>, security: SecurityCoordinator, rpcCoordinator: RPCCoordinator,
         pricesCoordinator: PricesCoordinator) {
        _network = network
        self.settings = settings
        _account = account
        self.security = security
        self.rpcCoordinator = rpcCoordinator
        self.pricesCoordinator = pricesCoordinator
    }

    var body: some View {
        @Bindable var settings = settings

        NavigationSplitView {
            SettingsSidebar(selection: $selection)
                .sidebarColumn()
        } detail: {
            switch selection {
            case nil:
                UnavailableScreen(title: "No Setting Selected",
                                  message: "Select a setting to change it.",
                                  systemImage: nil) {}
                    .toolbarTitleDisplayMode(.inline)
            case .accounts:
                AccountsScene(account: $account)
            case .security:
                SecurityScene(coordinator: security, account: account)
            case .appearance:
                NavigationStack {
                    AppearanceView(settings: settings)
                }
            case .network:
                NavigationStack {
                    NetworkScreen(network: $network)
                }
            case .rpc:
                RPCScene(coordinator: rpcCoordinator)
            case .currency:
                CurrencyScene()
            case .prices:
                PricesScene(coordinator: pricesCoordinator)
            }
        }
        .navigationSplitViewStyle(.tabSection)
        .onChange(of: selection) { _, selection in
            if selection != .security { security.close() }
            if selection != .rpc { rpcCoordinator.leave() }
            if selection != .prices { pricesCoordinator.leave() }
        }
        .alert(error: $settings.error)
    }
}
