import SwiftUI

/// Owns settings navigation and presentations within the window's appearance environment.
struct SettingsScene: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: SettingsDestination?
    let settings: AppearanceSettings
    let wallet: AppearanceWallet?
    let account: Account
    let security: SecurityFlow

    /// Presents the window's preference-editing workflow and its wallet's security choices.
    ///
    /// Appearance loading and rendering belong to the owning window's root.
    /// - Parameters:
    ///   - settings: The window's workflow; the window cancels unfinished work when it closes.
    ///   - wallet: The owning window's selected wallet theme scope, if one exists.
    ///   - account: The owning window's wallet, whose recovery Security & Privacy shows.
    ///   - security: The window's Security & Privacy navigation and steps.
    init(settings: AppearanceSettings, wallet: AppearanceWallet? = nil, account: Account, security: SecurityFlow) {
        self.settings = settings
        self.wallet = wallet
        self.account = account
        self.security = security
    }

    var body: some View {
        @Bindable var settings = settings

        NavigationSplitView {
            SettingsSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            switch selection ?? .appearance {
            case .appearance:
                NavigationStack {
                    AppearanceView(settings: settings, wallet: wallet)
                }
            case .security:
                SecurityScene(flow: security, account: account)
            }
        }
        .onChange(of: selection) { _, selection in
            // Leaving Security & Privacy closes its screens and releases any open backup.
            if selection != .security { security.close() }
        }
        .onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
            // A selection pushes its detail on compact displays, so only expanded layouts start with one.
            if sizeClass == .regular, selection == nil { selection = .appearance }
        }
        .alert("Appearance Unavailable", item: $settings.failure) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in Text(failure) }
    }
}
