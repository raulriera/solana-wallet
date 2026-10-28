import RPC
import SwiftUI

/// Owns a window's Settings tab: its Security & Privacy and Providers workflows, which the tab keeps while the person
/// switches tabs.
///
/// Leaving the wallet, as a reset does, ends the tab and its workflows with it.
struct SettingsScene: View {
    @State private var security: SecurityCoordinator
    @State private var providers: ProvidersCoordinator
    @Binding var network: Network
    let settings: AppearanceSettingsModel
    let account: Account

    /// Keeps the first workflows it receives for as long as the tab stays; later ones are discarded.
    /// - Parameters:
    ///   - settings: The window's appearance editing; the window cancels unfinished work when it leaves the wallet.
    ///   - account: The owning window's account, whose wallet's accounts Accounts lists and whose recovery Security &
    ///     Privacy shows.
    ///   - network: The network that the owning window shows; other windows keep theirs.
    ///   - security: New Security & Privacy navigation and steps for the tab.
    ///   - providers: New RPC provider choices and key entry for the tab.
    init(settings: AppearanceSettingsModel, account: Account,
         network: Binding<Network>, security: SecurityCoordinator, providers: ProvidersCoordinator) {
        self.security = security
        self.providers = providers
        _network = network
        self.settings = settings
        self.account = account
    }

    var body: some View {
        SettingsSplitView(settings: settings, account: account, network: $network, security: security,
                          providers: providers)
            .settingsLifecycle()
    }
}
