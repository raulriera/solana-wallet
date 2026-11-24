import SwiftUI

/// A section of choices for the price provider in use.
struct PriceSelectionSection: View {
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
                .lineLimit(1)
        } header: {
            Text("Price Provider")
        } footer: {
            Text("None turns prices off and makes no price requests.")
        }
    }
}
