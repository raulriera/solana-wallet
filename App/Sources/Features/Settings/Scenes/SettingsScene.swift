import RPC
import SwiftUI

/// Shows a window's Settings tab with its Security & Privacy and RPC workflows.
struct SettingsScene: View {
    @State private var security: SecurityCoordinator
    @State private var rpcCoordinator: RPCCoordinator
    @Binding var network: Network
    let settings: AppearanceSettingsModel
    @Binding var account: Account

    /// Creates the Settings tab.
    ///
    /// - Parameters:
    ///   - settings: The window's appearance settings workflow.
    ///   - account: The window's account.
    ///   - network: The window's network.
    ///   - security: The Security & Privacy workflow.
    ///   - rpcCoordinator: The RPC provider workflow.
    init(settings: AppearanceSettingsModel, account: Binding<Account>,
         network: Binding<Network>, security: SecurityCoordinator, rpcCoordinator: RPCCoordinator) {
        self.security = security
        self.rpcCoordinator = rpcCoordinator
        _network = network
        self.settings = settings
        _account = account
    }

    var body: some View {
        SettingsSplitView(settings: settings, account: $account, network: $network, security: security,
                          rpcCoordinator: rpcCoordinator)
            .settingsLifecycle()
    }
}
