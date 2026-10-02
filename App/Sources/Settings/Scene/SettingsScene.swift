import SwiftUI

/// Owns settings navigation and presentations within the window's appearance environment.
struct SettingsScene: View {
    @State private var settings: AppearanceSettings
    @State private var selection: SettingsDestination? = .appearance
    @State private var preferredColumn: NavigationSplitViewColumn = .detail
    let wallet: AppearanceWallet?

    /// Seeds this scene's independent preference-editing workflow once for its lifetime.
    ///
    /// Appearance loading and rendering belong to the owning window's root.
    /// - Parameters:
    ///   - settings: The workflow assembled for this scene, retained across view updates.
    ///   - wallet: The owning window's selected wallet, if one exists.
    init(settings: AppearanceSettings, wallet: AppearanceWallet? = nil) {
        self.settings = settings
        self.wallet = wallet
    }

    var body: some View {
        @Bindable var settings = settings

        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            SettingsSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            NavigationStack {
                switch selection ?? .appearance {
                case .appearance:
                    AppearanceView(settings: settings, wallet: wallet)
                }
            }
        }
        .alert("Appearance Unavailable", item: $settings.failure) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in Text(failure) }
        .onDisappear { settings.cancel() }
    }
}
