import SwiftUI

/// Owns a wallet window's sections behind a tab bar that always stays; each section owns its navigation.
///
/// The window reopens the section it showed when the system ended the app.
struct WalletScene: View {
    @SceneStorage("wallet.section") private var section = WalletSection.portfolio
    let account: Account
    let portfolio: any PortfolioCoordinating
    let settings: AppearanceSettings
    let connection: any ProviderConnecting
    let keyRevision: ProviderKeyRevision
    let security: SecurityFlow
    let resetRevision: AppResetRevision

    var body: some View {
        TabView(selection: $section) {
            Tab("Portfolio", systemImage: "wallet.bifold", value: .portfolio) {
                PortfolioScene(coordinator: portfolio, connection: connection, keyRevision: keyRevision)
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsScene(settings: settings, account: account, security: security)
                    .securityLifecycle(security)
            }
        }
        .tabViewStyle(.tabBarOnly)
        .portfolioObservation(of: account, coordinator: portfolio, keyRevision: keyRevision)
        // A reset deletes this wallet, so the next wallet opens on its portfolio.
        .onChange(of: resetRevision.value) { section = .portfolio }
        // Settings work belongs to the window, so switching tabs keeps an import or a saved choice going.
        .onDisappear { settings.cancel() }
    }
}
