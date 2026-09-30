import SwiftUI

/// Native icon-and-label navigation for the owning settings window.
struct SettingsSidebar: View {
    @Binding var selection: SettingsDestination?

    var body: some View {
        List(selection: $selection) {
            NavigationLink(value: SettingsDestination.appearance) {
                Label("Appearance", systemImage: "paintpalette")
            }
        }
        .labelStyle(.titleAndIcon)
        .listStyle(.sidebar)
        .navigationTitle("Settings")
    }
}
