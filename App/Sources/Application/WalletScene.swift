import SwiftUI

/// Owns a wallet window's sections behind a tab bar that always stays; each section owns its navigation.
struct WalletScene: View {
    @State private var section = WalletSection.portfolio
    let account: Account
    let portfolio: any PortfolioCoordinating
    let settings: AppearanceSettings
    let connection: any ProviderConnecting
    let keyRevision: ProviderKeyRevision

    var body: some View {
        TabView(selection: $section) {
            Tab("Portfolio", systemImage: "wallet.bifold", value: .portfolio) {
                PortfolioScene(coordinator: portfolio, connection: connection, keyRevision: keyRevision)
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsScene(settings: settings)
            }
        }
        .tabViewStyle(.tabBarOnly)
        .portfolioObservation(of: account, coordinator: portfolio, keyRevision: keyRevision)
        // Settings work belongs to the window, so switching tabs keeps an import or a saved choice going.
        .onDisappear { settings.cancel() }
    }
}
