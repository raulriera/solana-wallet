import RPC
import SwiftUI

/// Owns settings navigation and presentations within the window's appearance environment.
struct SettingsScene: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: SettingsDestination?
    @Binding var network: Network
    let settings: AppearanceSettingsModel
    let wallet: AppearanceWallet?
    let account: Account
    let security: SecurityCoordinator
    let providers: ProvidersCoordinator

    /// Presents the window's preference-editing workflow, its network, its RPC provider choices, and its wallet's
    /// security choices.
    ///
    /// Appearance loading and rendering belong to the owning window's root.
    /// - Parameters:
    ///   - settings: The window's workflow; the window cancels unfinished work when it closes.
    ///   - wallet: The owning window's selected wallet theme scope, if one exists.
    ///   - account: The owning window's wallet, whose recovery Security & Privacy shows.
    ///   - network: The network that the owning window shows; other windows keep theirs.
    ///   - security: The window's Security & Privacy navigation and steps.
    ///   - providers: The window's RPC provider choices and key entry.
    init(settings: AppearanceSettingsModel, wallet: AppearanceWallet? = nil, account: Account,
         network: Binding<Network>, security: SecurityCoordinator, providers: ProvidersCoordinator) {
        _network = network
        self.settings = settings
        self.wallet = wallet
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
                    AppearanceView(settings: settings, wallet: wallet)
                }
            case .network:
                NavigationStack {
                    NetworkScreen(network: $network)
                }
            case .providers:
                ProvidersScene(coordinator: providers)
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
