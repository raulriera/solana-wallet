import SwiftUI

/// Owns settings navigation and presentations within the window's appearance environment.
struct SettingsScene: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: SettingsDestination?
    let settings: AppearanceSettings
    let wallet: AppearanceWallet?
    let account: Account
    let recovery: any RecoveryRevealing
    let pasteboard: any RecoveryCopying

    /// Presents the window's preference-editing workflow and its wallet's security choices.
    ///
    /// Appearance loading and rendering belong to the owning window's root.
    /// - Parameters:
    ///   - settings: The window's workflow; the window cancels unfinished work when it closes.
    ///   - wallet: The owning window's selected wallet theme scope, if one exists.
    ///   - account: The owning window's wallet, whose recovery Security & Privacy shows.
    ///   - recovery: Reads the wallet's recovery after authentication.
    ///   - pasteboard: Copies recovery words to this device only, for a limited time.
    init(settings: AppearanceSettings, wallet: AppearanceWallet? = nil, account: Account,
         recovery: any RecoveryRevealing, pasteboard: any RecoveryCopying) {
        self.settings = settings
        self.wallet = wallet
        self.account = account
        self.recovery = recovery
        self.pasteboard = pasteboard
    }

    var body: some View {
        @Bindable var settings = settings

        NavigationSplitView {
            SettingsSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            NavigationStack {
                switch selection ?? .appearance {
                case .appearance:
                    AppearanceView(settings: settings, wallet: wallet)
                case .security:
                    SecurityScreen(account: account, recovery: recovery, pasteboard: pasteboard)
                }
            }
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
