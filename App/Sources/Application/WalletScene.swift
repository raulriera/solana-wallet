import RPC
import SwiftUI

/// Owns a wallet window's sections behind a tab bar that always stays; each section owns its navigation.
///
/// The window keeps the section with its scene state, so it reopens the section it showed when the system ended the app.
struct WalletScene: View {
    /// The window's appearance editing, kept outside the Settings tab so switching tabs keeps an import or a saved
    /// choice going; leaving the wallet cancels it.
    @State private var settings: AppearanceSettingsModel
    /// The section that the window shows.
    @Binding var section: WalletSection
    /// The network that the window shows, which Settings changes.
    @Binding var network: Network
    let account: Account
    let services: AppServices

    /// Keeps the first appearance editing it creates for as long as the window shows the wallet.
    /// - Parameters:
    ///   - section: The section that the window shows.
    ///   - network: The network that the window shows, which Settings changes.
    ///   - account: The window's account.
    ///   - services: The shared services that each section's workflows use.
    init(section: Binding<WalletSection>, network: Binding<Network>, account: Account, services: AppServices) {
        settings = services.makeAppearanceSettingsModel()
        _section = section
        _network = network
        self.account = account
        self.services = services
    }

    var body: some View {
        TabView(selection: $section) {
            Tab("Portfolio", systemImage: "wallet.bifold", value: .portfolio) {
                PortfolioScene(account: account, network: network, connection: services.providerConnection)
                    // Another account's or network's portfolio has its own tokens, so the tab starts again on the
                    // token list.
                    .id(network)
                    .id(account.id)
            }
            Tab("Contacts", systemImage: "person.crop.circle", value: .contacts) {
                ContactsScene(account: account, network: network)
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsScene(settings: settings, account: account, network: $network,
                              security: services.makeSecurityCoordinator(),
                              providers: services.makeProvidersCoordinator())
            }
        }
        .tabViewStyle(.tabBarOnly)
        .portfolioObservation(of: account, on: network)
        .privateBalanceObservation(of: account, on: network)
        .onDisappear { settings.cancel() }
    }
}
