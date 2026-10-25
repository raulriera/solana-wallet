import SwiftUI

/// Native icon-and-label navigation for the owning settings window.
struct SettingsSidebar: View {
    @ScaledMetric(relativeTo: .body) private var iconWidth = 28.0
    @Binding var selection: SettingsDestination?

    var body: some View {
        List(selection: $selection) {
            NavigationLink(value: SettingsDestination.appearance) {
                Label("Appearance", systemImage: "paintpalette.fill")
            }
            NavigationLink(value: SettingsDestination.network) {
                Label("Network", systemImage: "network")
            }
            NavigationLink(value: SettingsDestination.providers) {
                Label("Providers", systemImage: "point.3.filled.connected.trianglepath.dotted")
            }
            NavigationLink(value: SettingsDestination.currency) {
                Label("Currency", systemImage: "banknote.fill")
                    // The banknote has no colors of its own, so it takes money's green, as the other symbols take theirs.
                    .labelStyle(.sidebar(tint: .green))
            }
            NavigationLink(value: SettingsDestination.security) {
                Label("Security & Privacy", systemImage: "hand.raised.fill")
            }
        }
        .labelStyle(.sidebar)
        // Symbols differ in width, so a shared icon column keeps the titles aligned.
        .labelReservedIconWidth(iconWidth)
        .listStyle(.sidebar)
        .navigationTitle("Settings")
    }
}
