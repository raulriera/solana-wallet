import RPC
import SwiftUI

/// Shows the Settings destinations in a sidebar and the selected one's screens.
struct SettingsSplitView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: SettingsDestination?
    @Binding var network: Network
    let settings: AppearanceSettingsModel
    @Binding var account: Account
    let security: SecurityCoordinator
    let providers: ProvidersCoordinator

    /// Creates the Settings split view.
    ///
    /// - Parameters:
    ///   - settings: The window's appearance settings workflow.
    ///   - account: The window's account.
    ///   - network: The window's network.
    ///   - security: The Security & Privacy workflow.
    ///   - providers: The RPC provider workflow.
    init(settings: AppearanceSettingsModel, account: Binding<Account>,
         network: Binding<Network>, security: SecurityCoordinator, providers: ProvidersCoordinator) {
        _network = network
        self.settings = settings
        _account = account
        self.security = security
        self.providers = providers
    }

    var body: some View {
        @Bindable var settings = settings

        NavigationSplitView {
            SettingsSidebar(selection: $selection)
                .sidebarColumnWidth()
        } detail: {
            switch selection ?? .accounts {
            case .accounts:
                AccountsScene(account: $account)
            case .security:
                SecurityScene(coordinator: security, account: account)
            case .appearance:
                NavigationStack {
                    AppearanceView(settings: settings)
                }
            case .currency:
                CurrencyScene()
            case .network:
                NavigationStack {
                    NetworkScreen(network: $network)
                }
            case .providers:
                ProvidersScene(coordinator: providers)
            }
        }
        .navigationSplitViewStyle(.tabSection)
        .onChange(of: selection) { _, selection in
            if selection != .security { security.close() }
            if selection != .providers { providers.leave() }
        }
        .onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
            if sizeClass == .regular, selection == nil { selection = .accounts }
        }
        .errorAlert($settings.error)
    }
}
