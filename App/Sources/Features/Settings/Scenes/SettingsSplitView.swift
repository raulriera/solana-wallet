import RPC
import SwiftUI

/// Presents settings in a split view: the sidebar's destinations and the selected one's screens, within the window's
/// appearance environment.
struct SettingsSplitView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: SettingsDestination?
    @Binding var network: Network
    let settings: AppearanceSettingsModel
    let account: Account
    /// The tab's Security & Privacy navigation and steps, which run with ``settingsLifecycle()``.
    let security: SecurityCoordinator
    /// The tab's RPC provider choices and key entry, which run with ``settingsLifecycle()``.
    let providers: ProvidersCoordinator

    /// Presents the window's preference-editing workflow, its network, its wallet's accounts, its RPC provider choices,
    /// its currency, and its wallet's security choices.
    ///
    /// Appearance loading and rendering belong to the owning window's root.
    /// - Parameters:
    ///   - settings: The window's appearance editing; the window cancels unfinished work when it leaves the wallet.
    ///   - account: The owning window's account, whose wallet's accounts Accounts lists and whose recovery Security &
    ///     Privacy shows.
    ///   - network: The network that the owning window shows; other windows keep theirs.
    ///   - security: The tab's Security & Privacy navigation and steps.
    ///   - providers: The tab's RPC provider choices and key entry.
    init(settings: AppearanceSettingsModel, account: Account,
         network: Binding<Network>, security: SecurityCoordinator, providers: ProvidersCoordinator) {
        _network = network
        self.settings = settings
        self.account = account
        self.security = security
        self.providers = providers
    }

    var body: some View {
        @Bindable var settings = settings

        NavigationSplitView {
            SettingsSidebar(selection: $selection)
                .sidebarColumnWidth()
        } detail: {
            switch selection ?? .appearance {
            case .appearance:
                NavigationStack {
                    AppearanceView(settings: settings, wallet: nil)
                }
            case .network:
                NavigationStack {
                    NetworkScreen(network: $network)
                }
            case .accounts:
                AccountsScene(account: account)
            case .providers:
                ProvidersScene(coordinator: providers)
            case .currency:
                CurrencyScene()
            case .security:
                SecurityScene(coordinator: security, account: account)
            }
        }
        .navigationSplitViewStyle(.tabSection)
        .onChange(of: selection) { _, selection in
            // Leaving Security & Privacy closes its screens and releases any open backup.
            if selection != .security { security.close() }
            // Leaving Providers closes its screens.
            if selection != .providers { providers.leave() }
        }
        .onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
            // A selection pushes its detail on compact displays, so only expanded layouts start with one.
            if sizeClass == .regular, selection == nil { selection = .appearance }
        }
        .errorAlert($settings.error)
    }
}
