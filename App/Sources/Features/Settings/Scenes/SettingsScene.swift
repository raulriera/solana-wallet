import SwiftUI

/// Owns settings navigation and presentations within the window's appearance environment.
struct SettingsScene: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: SettingsDestination?
    let settings: AppearanceSettings
    let wallet: AppearanceWallet?
    let account: Account
    let security: SecurityFlow
    let providers: ProvidersFlow

    /// Presents the window's preference-editing workflow, its RPC provider choices, and its wallet's security choices.
    ///
    /// Appearance loading and rendering belong to the owning window's root.
    /// - Parameters:
    ///   - settings: The window's workflow; the window cancels unfinished work when it closes.
    ///   - wallet: The owning window's selected wallet theme scope, if one exists.
    ///   - account: The owning window's wallet, whose recovery Security & Privacy shows.
    ///   - security: The window's Security & Privacy navigation and steps.
    ///   - providers: The window's RPC provider choices and key entry.
    init(settings: AppearanceSettings, wallet: AppearanceWallet? = nil, account: Account, security: SecurityFlow,
         providers: ProvidersFlow) {
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
            case .providers:
                NavigationStack {
                    ProvidersScreen(flow: providers)
                        .providersLifecycle(providers)
                }
            case .security:
                SecurityScene(flow: security, account: account)
            }
        }
        .navigationSplitViewStyle(.tabSection)
        .onChange(of: selection) { _, selection in
            // Leaving Security & Privacy closes its screens and releases any open backup.
            if selection != .security { security.close() }
        }
        .onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
            // A selection pushes its detail on compact displays, so only expanded layouts start with one.
            if sizeClass == .regular, selection == nil { selection = .appearance }
        }
        .errorAlert($settings.error)
    }
}
