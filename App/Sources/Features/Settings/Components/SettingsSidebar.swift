import SwiftUI

/// The Settings sidebar's list of destinations.
struct SettingsSidebar: View {
    @ScaledMetric(relativeTo: .body) private var iconWidth = 28.0
    @Binding var selection: SettingsDestination?

    var body: some View {
        List(selection: $selection) {
            Section {
                NavigationLink(value: SettingsDestination.accounts) {
                    Label("Accounts", systemImage: "wallet.bifold.fill")
                        .labelStyle(.sidebar(tint: .brown))
                }
                NavigationLink(value: SettingsDestination.security) {
                    Label("Security & Privacy", systemImage: "hand.raised.fill")
                }
            }
            Section {
                NavigationLink(value: SettingsDestination.appearance) {
                    Label("Appearance", systemImage: "paintpalette.fill")
                }
                NavigationLink(value: SettingsDestination.network) {
                    Label("Network", systemImage: "network")
                }
            }
            Section {
                NavigationLink(value: SettingsDestination.rpc) {
                    Label("RPC", systemImage: "point.3.filled.connected.trianglepath.dotted")
                }
                NavigationLink(value: SettingsDestination.currency) {
                    Label("Currency", systemImage: "banknote.fill")
                        .labelStyle(.sidebar(tint: .green))
                }
            }
        }
        .labelStyle(.sidebar)
        .labelReservedIconWidth(iconWidth)
        .listStyle(.sidebar)
        .navigationTitle("Settings")
    }
}
