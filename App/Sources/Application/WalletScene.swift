import RPC
import SwiftUI

/// Shows a wallet window's sections in a tab bar.
struct WalletScene: View {
    @State private var settings: AppearanceSettingsModel
    @Binding var section: WalletSection
    @Binding var network: Network
    @Binding var account: Account
    let services: AppServices

    /// Creates a wallet scene.
    ///
    /// - Parameters:
    ///   - section: The section that the window shows.
    ///   - network: The network that the window shows.
    ///   - account: The account that the window shows.
    ///   - services: The shared services.
    init(section: Binding<WalletSection>, network: Binding<Network>, account: Binding<Account>, services: AppServices) {
        settings = services.makeAppearanceSettingsModel()
        _section = section
        _network = network
        _account = account
        self.services = services
    }

    var body: some View {
        TabView(selection: $section) {
            Tab("Portfolio", systemImage: "wallet.bifold", value: .portfolio) {
                PortfolioScene(account: account, network: network, connection: services.providerConnection)
                    .id(network)
                    .id(account.id)
            }
            Tab("Contacts", systemImage: "person.crop.circle", value: .contacts) {
                ContactsScene(account: account, network: network)
                    .id(network)
                    .id(account.id)
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsScene(settings: settings, account: $account, network: $network,
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
