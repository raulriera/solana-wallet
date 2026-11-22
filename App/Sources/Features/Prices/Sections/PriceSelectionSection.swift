import SwiftUI

/// A section of choices for the price provider in use.
struct PriceSelectionSection: View {
    @Environment(\.palette) private var palette
    /// The price provider in use, or `nil` before the choice is read.
    let selection: PriceSettings.Provider?
    let customServers: [URL]
    let actions: any PriceActions

    var body: some View {
        Section {
            PriceProviderRow(provider: .jupiter, isSelected: selection == .jupiter, actions: actions)
            PriceProviderRow(provider: .off, isSelected: selection == .off, actions: actions)
            ForEach(customServers, id: \.self) { url in
                PriceProviderRow(provider: .custom(url), isSelected: selection == .custom(url), actions: actions)
            }
            Button("Add Price Server…", systemImage: "plus", action: actions.addServer)
                .foregroundStyle(palette.primary)
                .lineLimit(1)
        } header: {
            Text("Price Provider")
        } footer: {
            Text("Token prices come from the provider you choose. None turns prices off and makes no price requests.")
        }
    }
}
