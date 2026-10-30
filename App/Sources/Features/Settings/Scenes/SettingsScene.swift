import RPC
import SwiftUI

/// Shows a window's Settings tab with its Security & Privacy and Providers workflows.
struct SettingsScene: View {
    @State private var security: SecurityCoordinator
    @State private var providers: ProvidersCoordinator
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
    ///   - providers: The RPC provider workflow.
    init(settings: AppearanceSettingsModel, account: Binding<Account>,
         network: Binding<Network>, security: SecurityCoordinator, providers: ProvidersCoordinator) {
        self.security = security
        self.providers = providers
        _network = network
        self.settings = settings
        _account = account
    }

    var body: some View {
        SettingsSplitView(settings: settings, account: $account, network: $network, security: security,
                          providers: providers)
            .settingsLifecycle()
    }
}
